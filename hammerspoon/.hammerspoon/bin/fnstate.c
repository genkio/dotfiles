// Toggle "Use F1, F2, etc. keys as standard function keys" for every keyboard.
//
// `defaults write -g com.apple.keyboard.fnState` only lands on disk; nothing
// running rereads it, so the setting appears unchanged until the next login.
// The live switch is the HIDFKeyMode parameter on IOHIDSystem, which is what
// System Settings drives. IOHIDSystem is machine-wide, so one write covers the
// internal and any external keyboard. The preference is mirrored afterwards so
// System Settings shows the same state and it survives a reboot.
//
// Usage: fnstate [get|on|off|toggle]   Prints the resulting state as 0 or 1.

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <stdio.h>
#include <string.h>

static const CFStringRef kFKeyModeKey = CFSTR("HIDFKeyMode");
static const CFStringRef kPrefKey = CFSTR("com.apple.keyboard.fnState");

static io_connect_t openHIDParamConnect(void) {
  io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"));

  if (!service) {
    return 0;
  }

  io_connect_t connect = 0;
  kern_return_t result = IOServiceOpen(service, mach_task_self(), kIOHIDParamConnectType, &connect);

  IOObjectRelease(service);
  return result == KERN_SUCCESS ? connect : 0;
}

static void mirrorPreference(int state) {
  CFPreferencesSetValue(kPrefKey, state ? kCFBooleanTrue : kCFBooleanFalse, kCFPreferencesAnyApplication,
                        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
  CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

int main(int argc, char **argv) {
  const char *command = argc > 1 ? argv[1] : "toggle";
  io_connect_t connect = openHIDParamConnect();

  if (!connect) {
    fprintf(stderr, "fnstate: could not open IOHIDSystem\n");
    return 1;
  }

  uint64_t current = 0;
  IOByteCount actualSize = 0;

  if (IOHIDGetParameter(connect, kFKeyModeKey, sizeof current, &current, &actualSize) != KERN_SUCCESS) {
    fprintf(stderr, "fnstate: could not read HIDFKeyMode\n");
    IOServiceClose(connect);
    return 1;
  }

  if (strcmp(command, "get") == 0) {
    printf("%d\n", current ? 1 : 0);
    IOServiceClose(connect);
    return 0;
  }

  uint64_t next;

  if (strcmp(command, "on") == 0) {
    next = 1;
  } else if (strcmp(command, "off") == 0) {
    next = 0;
  } else if (strcmp(command, "toggle") == 0) {
    next = current ? 0 : 1;
  } else {
    fprintf(stderr, "fnstate: usage: fnstate [get|on|off|toggle]\n");
    IOServiceClose(connect);
    return 2;
  }

  kern_return_t result = IOHIDSetParameter(connect, kFKeyModeKey, &next, sizeof next);

  IOServiceClose(connect);

  if (result != KERN_SUCCESS) {
    fprintf(stderr, "fnstate: could not set HIDFKeyMode\n");
    return 1;
  }

  mirrorPreference((int)next);
  printf("%d\n", (int)next);
  return 0;
}
