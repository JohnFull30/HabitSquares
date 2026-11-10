# HabitSquares — first internal TestFlight candidate

November 9, 2026. Ready for the first **internal habit-tracking beta upload**, pending the owner's explicit upload approval. No build has been uploaded to Apple.

## Candidate

- App Store Connect app: **HabitSquares: Habit Builder**, Apple ID **6832772417**; verified in the **John Fuller** personal account.
- Bundle: **PullerLabs.Habit-Tracker**. Widget: **PullerLabs.Habit-Tracker.Habit-Tracker-Widget**.
- Signing team: **John Fuller / CRF77UR32V**. App Group: **group.pullerlabs.habitsquares**.
- Version **1.0**, build **1**. The TestFlight page currently has no builds.
- Release archive and App Store Connect **export** succeeded. Xcode automatic provisioning resolved the missing App Store distribution profiles. App and widget distribution signatures verify locally, include `beta-reports-active`, and have `get-task-allow=false`.
- Both privacy manifests are bundled. Source functionality is unchanged from the tested Phase 2 fixes. The only additional project change declares `ITSAppUsesNonExemptEncryption=false` in the active app Info.plist: source/dependency inspection found only Apple-platform encryption, no custom or non-exempt encryption implementation. [Apple's declaration guidance](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).
- Earlier Phase 2 validation passed all 17 regression methods and the UI suite. The final metadata-only change was checked through a fresh signed Release archive and distribution export; functional tests were not repeated for this Boolean plist declaration.

## Physical-device preservation check

With the owner's explicit approval, the running app was gracefully closed, its complete app container and App Group were backed up outside the repository, and the development-signed Release app was installed **in place** on John's iPhone 17 Pro. No uninstall or reset command was issued. The app launched successfully and remained running. It was closed briefly to obtain a consistent post-launch copy for comparison, then reopened.

A recovered standalone SQLite backup passed `PRAGMA integrity_check`. Logical before/after comparison of every original row showed:

| Data | Before | After | Missing rows | Changed rows |
|---|---:|---:|---:|---:|
| Habits | 3 | 3 | 0 | 0 |
| Habit completions | 1,148 | 1,148 | 0 | 0 |
| Reminder links | 2 | 2 | 0 | 0 |

The persistent-store UUID is unchanged. The original model, store initializer/location, bundle IDs, team, App Group and StoreKit product IDs are unchanged. This verifies upgrade/launch data preservation; it does not replace hands-on recurrence, permission, midnight/widget, purchase or keyboard/sheet testing.

Private backup location (not committed):
`/Users/John/Library/Application Support/HabitSquares Release Backups/pre-testflight-20261109-201314/`

The backup includes original/quiescent app containers, original App Group data, `VerifiedHabitModel.sqlite`, checksums and a post-upgrade comparison. Do not delete or overwrite it during beta preparation.

## Saved artifacts

Archive, available to Xcode Organizer:
`/Users/John/Library/Developer/Xcode/Archives/2026-11-09/HabitSquares-TestFlight-1.0-1.xcarchive`

Distribution IPA and export evidence:
`/Users/John/Library/Developer/Xcode/Exports/HabitSquares-1.0-1-20261109/habitSqaures.ipa`

IPA SHA-256:
`cdb4b42041bbf00b283c035adde0a44a0363378c577182c8019574fd09a2b7a9`

Build/export/device logs are under `/tmp/habitsquares-testflight-ready/` and may be cleaned by macOS. No private data backup, signing private key, credential or IPA is stored in Git.

## Next step and remaining scope

1. Owner approval is required before uploading this build to App Store Connect, per the existing instruction. After approval, validate/upload the saved candidate, wait for Apple processing, resolve any processing/compliance errors, and prepare internal testing. Uploading a beta is not public App Store publication. Do not submit the public app version for review or publish it.
2. App Store Connect's In-App Purchases catalog is **empty**. Local .storekit products do not populate TestFlight's catalog. Pro/tips cannot be validated or expected to load until those records are configured. The owner has been asked whether to configure existing products first or start with the free habit-tracking beta; no products/prices have been created or changed remotely. Existing configured test prices are $29.99 lifetime Pro; $1.99/$4.99/$9.99/$24.99 tip tiers; $0.99 tip unit. Preserve their exact existing IDs.
3. Internal testers/groups can be configured after the processed build exists. No invitations have been sent and no external beta review requested. External testing, public release metadata/screenshots, legal agreements and financial/tax details remain separate steps; do not accept agreements on the owner's behalf.
4. Apple server-side validation and processing are not yet proven by a local archive/export. The installed toolchain is Xcode 27.2 (27B52), iOS 27.2 SDK; Apple must accept the uploaded binary before TestFlight can start.
5. Hands-on testing of recurring reminders, permission revocation, widget scheduling, sandbox purchases and original keyboard/sheet rectangle diagnostics remains appropriate **inside** the beta. Data-protection tests and the in-place launch check passed; no speculative diagnostic workaround or CloudKit capability was added.
