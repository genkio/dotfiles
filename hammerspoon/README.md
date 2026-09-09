# UURemote monitoring

`init.lua` starts both scripts only when `/Applications/UURemote.app` exists as a directory.
It also skips the monitor if `uuremote_monitor.lua` is absent.
Both subscribe to `uuremote_probe.lua`, which runs every two seconds.
The lock script retains its existing screensaver behavior.

## Use on another Mac

1. Install Hammerspoon and UURemote in `/Applications`.
2. Apply this package with `cd ~/dotfiles && stow hammerspoon`.
3. Start Hammerspoon, or select **Reload Config** from its menu.

Tailscale is optional. Its local inventory supplies names for known Tailscale addresses.
If no device name is available, the log retains IP addresses without a device label.
A device name does not prove who used that device.

The screensaver requires an immediate macOS password requirement to lock the Mac.
UURemote's own lock-on-disconnect setting must remain off for the existing screensaver behavior.

## Remove the monitor

Delete `uuremote_monitor.lua`, then reload Hammerspoon.
The startup code skips the absent monitor. The lock script continues without it.
Keep `uuremote_probe.lua`: the lock script uses this shared probe.
Deleting the monitor does not delete existing logs.

## Logs

The active file is `hammerspoon/.hammerspoon/logs/uuremote/events.log` inside this repository.
`events.jsonl` is historical output from the previous writer. It receives no new entries.
Git ignores the log directory. Its mode is `700`. Each Mac keeps its own logs.

The monitor writes two lines per observed connection, using logfmt. The following names and addresses are synthetic examples:

```text
time=2025-01-15T10:00:00+01:00 peers="phone@192.0.2.10" level=info msg=connect terminal=true
time=2025-01-15T10:00:26+01:00 peers="phone@192.0.2.10" level=info msg=disconnect terminal=true duration_seconds=26 connected_at=2025-01-15T10:00:00+01:00
```

Open the active file with lnav:

```sh
lnav ~/dotfiles/hammerspoon/.hammerspoon/logs/uuremote/events.log
```

lnav recognizes [logfmt directly](https://docs.lnav.org/en/stable/formats.html#logfmt), without a custom format file.
It parses the time, level, and message. Extra fields are available in the `logfmt_log` SQL table's `fields` column.

| Field | Meaning |
| --- | --- |
| `time` | Local observation time with timezone offset. `+01:00` means one hour ahead of UTC. |
| `level` | Always `info`. Supplies the severity field for log viewers. |
| `msg` | `connect` when activity appears, or `disconnect` after two polls without detected activity. |
| `peers` | Comma-separated identified devices as `name@ip`. If none are identified, contains IP addresses only. Empty means no qualifying IP was observed. |
| `terminal` | Present as `true` if an attached UURemote terminal helper was observed. Absence does not prove desktop mode. |
| `monitoring_gap` | Present as `true` if a probe failed during the interval. Absence does not guarantee complete visibility. |
| `duration_seconds` | Disconnect only. Elapsed seconds from initial detection through confirmed disconnect, including the polling delay. |
| `connected_at` | Disconnect only, always last. Matches the connect line's `time`. |

The monitor keeps one address per identified Tailscale device and prefers IPv4.
If any identified devices are present, the log omits unidentified addresses to reduce noise.
These omitted addresses can include other clients. This compact log is not a complete network audit.

The connect entry waits for a terminal helper or approximately four seconds of observed activity.
Its timestamp remains the time when activity first appeared. Short connections still produce both lines.
A helper that appears later can still produce `terminal=true` only on disconnect.
The disconnect entry includes any device names and terminal activity learned after the connect entry.

At 5 MiB, the monitor rotates the file and keeps five archives (`events.log.1` through `.5`).
Idle polling, socket changes, startup, and device inventory refreshes produce no log entries.
Probe and write errors appear in the Hammerspoon console.
Failed writes retain the pending connection state for retry. Historical missing disconnect times cannot be reconstructed from these logs.

## Limits

Detection uses non-443 established TCP connections or an attached terminal helper.
Two empty polls confirm a disconnect. Socket changes within a connection do not create extra entries.
Concurrent remote clients form one combined interval, ending when all detected activity stops.

A session through port 443 alone is undetectable unless its terminal helper appears.
A two-second poll can miss shorter connections. UDP traffic, packet contents, commands, and screen images are outside this monitor's scope.
The lock script retains its non-443 TCP heuristic.

The monitor uses observations from UURemote 4.39.0. App updates can change these signals.
Hammerspoon must remain active. After a restart, existing activity starts a new observed interval.
A shutdown or crash can leave a connect entry without a disconnect entry.
Local logs are not tamper-proof. The monitor does not prevent access or send alerts to another device.
