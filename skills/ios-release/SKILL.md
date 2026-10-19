---
name: ios-release
description: Take an iOS app from a local Xcode or xcodegen project to TestFlight and App Store review with the asc CLI and an App Store Connect API key, without signing in to Xcode with an Apple ID. Use when setting up App Store Connect for a new app, uploading a TestFlight build, preparing the App Store listing and screenshots, adding in-app purchases, or submitting for review.
---

# iOS release

Ship an iOS app through App Store Connect from the terminal. Every App Store Connect call goes through the `asc` CLI with an API key, and Xcode signs with the same key, so no Apple ID is ever signed in to Xcode. Each repo pins exactly one asc profile, which keeps apps on different developer teams from mixing.

The rorkai `asc-*` skills document individual commands, and `app-store-screenshots` covers the screenshot editor. This skill is the order of work and the problems that aren't obvious from those.

Never put a key ID, issuer ID, team ID, email or phone number in a public repo. They live in `~/.asc/config.json` and are read at run time.

## Order of work

1. Machine setup (once per team).
2. Repo setup.
3. Project check.
4. Bundle ID and app record.
5. Upload a build, then TestFlight.
6. Listing, screenshots, and the remaining version fields.
7. In-app purchases, if any.
8. Submit for review.

The task is done when `asc review status --app <APP_ID>` shows the version waiting for review. Report back then; don't poll.

Before any command that publishes or replaces something in App Store Connect (`metadata apply`, `screenshots upload --replace`, a review submission), show the plan or dry run and get the user's go.

## 1. Machine setup

Create a Team Key with Admin access in App Store Connect (Users and Access › Integrations). Keep the `.p8` at `~/.asc/keys/AuthKey_<KEY_ID>.p8` with mode 600, and back it up: Apple never lets you download it again.

Register it as a named profile in the config file. The keychain backend fails from non-GUI shells with `Keychain Error. (-61)`:

```sh
asc auth login --bypass-keychain --name <profile> --key-id <KEY_ID> --issuer-id <ISSUER_ID> \
  --key-type team --private-key ~/.asc/keys/AuthKey_<KEY_ID>.p8 --network
```

Then clear the top-level `key_id`, `issuer_id`, `private_key_path` and `default_key_name` in `~/.asc/config.json`, so no profile is the global default and each repo must pin one.

Put `scripts/ios-testflight` from this skill's directory on the PATH with a symlink.

## 2. Repo setup

1. Install the skill packs into the repo and commit `skills-lock.json`: `npx skills add rorkai/app-store-connect-cli-skills ParthJadhav/app-store-screenshots`.
2. Pin the profile in `.asc/config.json` at the repo root and commit it. Add `app_id` once the app exists:
   ```json
   { "default_key_name": "<profile>", "app_id": "<APP_ID>" }
   ```
3. Add `.asc/*` and `!.asc/config.json` to `.gitignore`. Build artifacts go to `.asc/artifacts/`.
4. Run `asc apps list` from the repo: it must show this team's apps.
5. Run `asc web agreements status`. A pending Paid Applications Schedule blocks in-app purchases and new app submissions, even free ones; only the account holder can accept it, in App Store Connect › Business.

## 3. Project check

- With xcodegen, `supportedDestinations: [iOS]` sets `TARGETED_DEVICE_FAMILY = "1,2"` on every target, overriding a project-level `"1"`. An iPhone-only app then fails processing with ITMS-90474. Set `TARGETED_DEVICE_FAMILY: "1"` on each target.
- Set `ITSAppUsesNonExemptEncryption: false` in Info.plist if it applies, so builds skip the export-compliance question.
- The build number must come from `CURRENT_PROJECT_VERSION`, which `ios-testflight` sets: either `GENERATE_INFOPLIST_FILE: YES`, which overrides a literal `CFBundleVersion` in Info.plist, or `CFBundleVersion` set to `$(CURRENT_PROJECT_VERSION)`.

## 4. Bundle ID and app record

Register the bundle ID first if it isn't already (`asc bundle-ids create`, see `asc-signing-setup`). Creating the app needs a web session as the account holder, so the user runs the login (password and 2FA):

```sh
asc web auth login --apple-id <apple-id> --provider-id <numeric-provider-id>
```

`--public-provider-id` takes a UUID, not the team ID, though its `--help` says team ID; a wrong value makes the error list both IDs. Then:

```sh
asc web apps create --name "<Store name>" --bundle-id <bundle-id> --sku <sku> \
  --primary-locale en-US --version 1.0 --platform IOS --auto-rename=false
```

Check it with `asc apps list --bundle-id <bundle-id>`: seeing it through the API key confirms it landed on the right team.

## 5. Build and TestFlight

Run `ios-testflight --dry-run` to see the resolved project, scheme, bundle ID, team, key and next build number, then `ios-testflight [dir] [--scheme NAME] [--wait]` to archive, sign and upload. Signing needs the login keychain, so from a non-GUI shell it builds in a Terminal window and waits. Processing errors arrive by email, not in the upload output; wait for `VALID` in `asc builds list` before using a build.

For testing, create an internal group with `--internal --access-all-builds` and add the account holder; internal builds need no beta review.

## 6. Listing and version fields

Keep the listing in `metadata/` and publish it with `asc metadata pull`, `plan`, `approve --all`, `apply --confirm`. Keywords are capped at 100 characters, and words already in the name or subtitle are wasted. Don't put a currency price in the description. A privacy policy URL is required.

For screenshots, capture the iPhone Pro Max simulator after `xcrun simctl status_bar <SIM> override --time 9:41 --batteryState charged --batteryLevel 100`; a launch argument that opens each screen in a demo state makes captures repeatable. Build the deck with `app-store-screenshots`, then upload only the 6.9" set, which App Store Connect scales down: `asc screenshots upload ... --device-type IPHONE_69`.

`asc validate --app <APP_ID> --version <v> --platform IOS` lists what's still missing. The usual fields:

- Category: `asc categories set`.
- Age rating: `asc age-rating edit --all-none` when nothing applies.
- Copyright: `asc versions update --copyright`. Content rights: `asc apps content-rights edit --uses-third-party-content`.
- Price and availability: `asc pricing schedule create`, `asc pricing availability create --all-territories`. Leave China mainland (CHN) out at launch: apps with generative AI need a Chinese license, and MIIT may require an ICP filing number. `create` can't combine `--all-territories` with `--territory`, so take CHN out afterwards with `asc pricing availability edit --territory CHN --available false`. Availability changes don't need review, so it can be added later.
- App Review contact and notes: `asc review details-create`. It once came back with `demoAccountRequired: true` unasked; read it back with `asc api GET /v1/appStoreReviewDetails/<ID>` and fix with `details-update --demo-account-required=false`.
- App Privacy: `asc web privacy pull`, edit the JSON, then `plan`, `apply --confirm` (`--allow-deletes` to remove a type) and `publish --confirm`.
- Regulations: `asc web apps declarations list`, then `asc web apps medical-device set --declared false` for non-medical apps.

An individual account's store seller name is the account holder's legal name and can't be changed.

## 7. In-app purchases

Create each product with `asc iap setup --app <APP_ID> --type <TYPE> --product-id <id> --price <price> --base-territory <territory>` plus a display name and description. A product stays `MISSING_METADATA`, and StoreKit won't return it even in TestFlight, until it also has availability (`asc iap pricing availability set`) and an App Review screenshot (`asc iap review-screenshots create`, no alpha channel, so convert simulator PNGs to JPEG). A $0 non-renewing subscription used as a free trial never came back from StoreKit. Apple's guideline 3.1.1 describes the trial as a non-consumable at price tier 0 named like "14-day Trial"; the other way is to count the trial in the app from `AppTransaction.originalPurchaseDate`. TestFlight purchases are free sandbox purchases.

## 8. Submit for review

Attach the build and validate in one step with `asc release stage --app <APP_ID> --version <v> --build-id <BUILD_ID> --metadata-dir ./metadata`, `--dry-run` first, then `--confirm` (or `asc versions attach-build`, then `asc validate`). Two `validate` notes are info only and never block: App Privacy can't be checked through the API, and an iPhone-only app still gets a missing-iPad-screenshots note. Check `asc review submissions list` for an existing submission.

Without in-app purchases, submit with `asc review submit --app <APP_ID> --version <v> --build-number <n>`, `--dry-run` first, then `--confirm`. A first in-app purchase must go to review with an app version, so build a multi-item submission and add only the products that should go live. `asc iap versions list --iap-id <IAP_ID>` gives the IAP version ID:

```sh
asc review submissions-create --app <APP_ID> --platform IOS
asc review items add --submission <ID> --item-type appStoreVersions --item-id <VERSION_ID>
asc review items add --submission <ID> --item-type inAppPurchaseVersions --item-id <IAP_VERSION_ID>
asc review submissions-submit --id <ID> --confirm
```

A submission cancelled in App Store Connect leaves the version and its IAP versions `DEVELOPER_REJECTED`. Keep the same version: upload a new build, stage it onto the version, and submit a new multi-item submission with the same items.

The release type defaults to after approval, so an approved version goes live on its own.

For later versions: `asc versions create`, write What's New under `metadata/version/<v>/`, upload a build, attach it, and submit the same way.

Never delete an app record, build or in-app purchase unless the user asks: a deleted product ID can never be reused. Leave an unused product unsubmitted instead.
