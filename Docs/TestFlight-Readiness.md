# HabitSquares — TestFlight status

November 9, 2026. The owner chose **Start the free habit-tracking beta first**. Version **1.0 (1)** was uploaded to the personal John Fuller team and Apple completed processing. App Store Connect now reports **Testing**, assigned to **HabitSquares Internal**. External build **1.0 (2)** has also been uploaded and is **Waiting for Review** for the owner's requested external tester. No public App Store submission or publication was performed.

## Initial internal candidate (build 1)

- App Store Connect app: **HabitSquares: Habit Builder**, Apple ID **6832772417**; verified in the **John Fuller** personal account.
- Bundle: **PullerLabs.Habit-Tracker**. Widget: **PullerLabs.Habit-Tracker.Habit-Tracker-Widget**.
- Signing team: **John Fuller / CRF77UR32V**. App Group: **group.pullerlabs.habitsquares**.
- Version **1.0**, build **1**, now **Testing** in App Store Connect. Upload completed at 8:22 PM Eastern on November 9; the UI displays an 8:23 PM upload time. The build expires in 90 days.
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

Locally exported IPA SHA-256 (the upload reused the same archive with internal-only distribution enabled):
`cdb4b42041bbf00b283c035adde0a44a0363378c577182c8019574fd09a2b7a9`

Build/export/device logs are under `/tmp/habitsquares-testflight-ready/` and may be cleaned by macOS. No private data backup, signing private key, credential or IPA is stored in Git.

## TestFlight access and remaining scope

- Build **1.0 (1)** is **Testing**, assigned to **HabitSquares Internal**. The group was created with automatic distribution **disabled**, so future builds require deliberate assignment.
- The internal group contains only the owner's existing App Store Connect account. The separately requested external tester is handled in the external group described below. Open the TestFlight invitation on the iPhone using the same Apple Account, then accept and install HabitSquares. Keep the existing app installed; do not delete or reset it.
- Upload options set `testFlightInternalTestingOnly=true`. This build cannot be used for external TestFlight testing or public App Store distribution. A later build is needed for those purposes. No App Store version was submitted for public review and no public release was triggered.
- Pro/tips setup is deferred at the owner's request. The App Store Connect purchase catalog remains empty and unchanged; local .storekit products do not populate it. The beta retains the existing free limit of three habits. Existing habits are retained; purchase testing is not available yet.
- Apple server-side package analysis, upload and processing succeeded for the installed Xcode 27.2 toolchain. No additional encryption questionnaire blocked internal testing.
- Hands-on testing of recurring reminders, revoked permissions, midnight/widget scheduling and original keyboard/sheet rectangle diagnostics remains part of the beta. Data-protection regression tests and the in-place device launch/history check passed.

[Internal testing group](https://appstoreconnect.apple.com/teams/c99052d5-6cb9-4270-b7d5-92fb219e07a0/apps/6832772417/testflight/groups/69db7478-cc5c-4d1e-9fd6-96f366061712)

[Build 1](https://appstoreconnect.apple.com/teams/c99052d5-6cb9-4270-b7d5-92fb219e07a0/apps/6832772417/testflight/ios/38b41620-c4bd-4d4f-b9f3-9dccc1999256)

Upload log: `/tmp/habitsquares-testflight-ready/upload.log`. Persistent upload receipt: `/Users/John/Library/Developer/Xcode/Exports/HabitSquares-1.0-1-20261109/Upload-Receipt.txt`.

## External tester and build 2

At the owner's request, one external tester was added to **HabitSquares External** by email. No App Store Connect user account, administrative role or public invitation link was created for that person. Contact addresses and the review phone number are stored only in App Store Connect, not in this repository.

Build 1 was intentionally restricted to internal TestFlight testing. A fresh Release archive of the same functional source was built as **1.0 (2)** with external eligibility enabled, uploaded successfully, and processed by Apple. The app and widget shipping build numbers in the project now both read **2** for Debug and Release. Bundle IDs, developer team, App Group, Core Data model and persistent store initialization are unchanged. No new personal-device installation or data modification was needed for this metadata-only build increment.

The external group has build **1.0 (2)** assigned. Its observed status is **Waiting for Review** after successful submission to **Beta App Review**. Automatic tester notification is enabled. The tester cannot install until Apple approves; Apple will then send the TestFlight invitation automatically. The internal group remains on build 1 and continues testing independently.

Beta description, review instructions and What to Test were saved. Review information explicitly says the app requires no sign-in account, describes Apple Reminders permission and a recurring reminder due today, and identifies the three-habit free beta and unconfigured Pro/tip purchase testing. The owner supplied a review phone and approved separate review-contact and tester-feedback addresses, which were saved remotely without recording them in Git.

Validation: the Release archive for build 2 succeeded; app and embedded widget Info.plists both have version 1.0/build 2 and retain the original bundle IDs. Apple package analysis, upload and processing succeeded. Project plist syntax and whitespace checks pass. Existing Phase 2 functional tests were not repeated because this upload changes only the build number and TestFlight distribution eligibility.

[External testing group](https://appstoreconnect.apple.com/teams/c99052d5-6cb9-4270-b7d5-92fb219e07a0/apps/6832772417/testflight/groups/f2ae265b-7690-470b-95e5-49bf80205709)

[Build 2](https://appstoreconnect.apple.com/teams/c99052d5-6cb9-4270-b7d5-92fb219e07a0/apps/6832772417/testflight/ios/c90ca2f7-e967-4b76-a008-ef1fa2181361)

Archive: `/Users/John/Library/Developer/Xcode/Archives/2026-11-09/HabitSquares-External-1.0-2.xcarchive`.

Upload log: `/tmp/habitsquares-testflight-ready/upload-external-2.log`. No public App Store review or release was submitted. No agreement, tax/banking information or purchase products were changed.
