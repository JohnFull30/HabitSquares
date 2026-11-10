# HabitSquares TestFlight preparation — Phase 2

November 9, 2026. Based on `df6a46d` on branch `codex/testflight-phase2`. Functional fixes are in `86d0a0c`; the follow-up batches history lookups and records final validation.

## Changes and preservation policy

- History backfill is insert-only: existing completion IDs, dates, counts, status and source are never rewritten. Existing completion days are fetched once per habit to avoid repeated main-thread day queries. Only positive EventKit evidence fills missing past days; missing history does not create false rows. History backfill excludes today so it cannot race the live writer. The successful-backfill preference is set only after fetch and save succeed.
- Today sync updates only new rows tagged `reminders`. Existing legacy/manual/seed rows remain intact, including today's row on the upgrade day. Tomorrow, newly created live rows can complete and uncomplete normally when all required links resolve to fetched reminders. No required links, missing identifiers, incomplete fetch evidence, and duplicate stored rows cannot clear a square. Fetch failures propagate instead of becoming empty Core Data results.
- Linking no longer writes or commits EventKit reminders. It stores the existing stamp (if present), otherwise external/item identity, in existing Core Data attributes. Original URL, notes, recurrence, dates and other metadata are untouched. The save path rechecks existing links, prevents duplicate links and retains the sheet with an error when saving fails. Failed unsaved insertions from that attempt are discarded without a context-wide rollback.
- A shared guarded identity reader supports `reminderIdentifier`, `reminderKey`, `ekReminderID` and legacy aliases. Missing model keys cannot cause the old undefined-key exception. Editing, metadata refresh, completion matching and picker classification use the same keys; old URL stamps remain readable.
- The widget reads a selected-habit file only if that habit is in the current index and the payload ID matches. Orphaned files are retained, not deleted. A removed selection renders empty instead of another habit's data. When a widget reloads after midnight, the historical grid remains available while stale “Done/remaining” summaries are hidden. One writer refreshes index, per-habit and aggregate caches; numeric counts use NSNumber bridging. Failed Core Data fetches preserve the previous valid cache.
- Both app configurations display **HabitSquares**. Bundle IDs, target/module names, team, App Group, model bytes, store initialization/location and StoreKit product IDs are unchanged.
- The shared test scheme includes unit and UI targets, unit tests import `habitSqaures`, and the UI-test target points at the existing `habitSqaures` app target.

## Required-reason API audit

AppStorage accesses app-local preferences (`hasSeenOnboarding`, `lastHistoryBackfillDay`). The app manifest declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`. The widget directly uses JSON files in the existing App Group; it does not directly use UserDefaults, so its separate manifest has no accessed-API categories.

Source audit found no direct file timestamp, disk-space, system boot-time or active keyboard API calls; file existence and JSON read/write operations do not by themselves access those values. No third-party dependencies, analytics/tracking implementation or developer-operated network collection endpoint was found. Both manifests declare no tracking, tracking domains or collected data. EventKit data remains local to the app/system accounts and StoreKit uses Apple's framework; App Store privacy answers and policy still need owner review before submission.

Both manifests are explicit Copy Bundle Resources entries and must be verified in the built app and embedded extension. References: [Apple required-reason API documentation](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [Apple TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).

## Validation

- Signed generic-device Release build: **passed** using existing John Fuller development profiles, app plus widget. No compiler warnings/errors in the final Release log. Distribution export was not attempted.
- Full shared-scheme test run: **passed**, 17 regression methods plus 3 UI methods (6 UI executions, including launch screenshots in four appearance/orientation configurations). xcresult summary reports 20 distinct tests passed, zero failures and zero skipped tests.
- After the final batched-history adjustment: **all 17 regression tests passed again**, zero failures (0.228 seconds of test execution).
- Built products verified: main display name HabitSquares; app/widget bundle IDs and signed team/App Group match baseline; each executable contains its intended PrivacyInfo.xcprivacy. Plists and project syntax validate; git diff whitespace check passes.
- Byte comparisons against `df6a46d` confirm the Core Data model, persistence initializer, all entitlements, StoreKit configuration and PurchaseManager are unchanged. Build-setting comparisons confirm bundle IDs, team, entitlement paths, deployment target and version/build values are unchanged.
- The test-bundle build emits an informational AppIntents metadata-extraction warning because that test bundle does not depend on AppIntents. Simulator/Xcode also emit accessibility/debugger diagnostics; they did not fail the tests. Initial fixture model-lookup warnings were removed by sharing the production model instance across fixture containers.

Tests use a newly created simulator, in-memory stores and disposable temporary SQLite/cache fixtures. They do not open, reset or migrate the personal device store. No uninstall commands were issued.

Regression cases cover immutable historical rows and provenance; positive/idempotent gap filling; zero/missing/optional links; today complete/uncomplete; isolation between habits; original reminder metadata and stamps; safe legacy keys; duplicate link saving and failed-save isolation; SQLite reopen with stable IDs, history and links; deleted widget selections without file deletion; widget numeric counts, midnight staleness and interrupted aggregate publication.

## Remaining release gates

1. Back up the personal app container consistently before any physical-device upgrade test; upgrade in place and compare real habit IDs, links and complete history. Do not uninstall or reset. No schema change or migration is introduced here, and no compatibility claim is made for unknown older model versions. The existing store-load-failure path still logs an error; it does not reset/recreate the store or provide an in-app recovery flow.
2. Test real account identity/recurrence behavior, read-only calendars, revoked/regranted permissions, offline changes, DST/time-zone/day boundaries and reminders with existing URLs. EventKit identifiers may change after account rebuilds; unknown links are retained rather than repaired by guessing. URLs overwritten by older builds cannot be reconstructed automatically.
3. Confirm real widget configurations on device after edit/delete/upgrade and midnight. The widget cannot discover a deletion until the app refreshes its index; WidgetKit scheduling and multi-file publication are not transactional or immediate.
4. The conservative policy freezes existing legacy rows, including an existing row on upgrade day. Historical false/partial rows are retained even if later EventKit evidence differs. Automatically correcting these would require a separate, reviewable reconciliation policy.
5. Reproduce the keyboard/sheet rectangle-conversion diagnostics on the original device and OS. No speculative UI workaround is included. Escalate if visible layout, keyboard or interaction is affected.
6. Sandbox StoreKit purchase/restore/pending/refund and existing-user limits still need device testing. Products/configuration are unchanged. App Store Connect record and IAP readiness were not modified or independently verified.
7. A development-signed Release build is not a distribution export. Verify toolchain acceptance, distribution signing, archive validation, privacy answers and beta information before upload. No archive export, upload or publishing is authorized/performed in this phase.

## Reproduction commands and evidence

From `/Users/John/Developer/Habit Tracker`:

```sh
xcodebuild -project habitSqaures.xcodeproj -scheme 'Habit Tracker' -destination 'platform=iOS Simulator,id=02F1EF02-1EAC-456D-B953-FB4D674D3538' -derivedDataPath /tmp/habitsquares-phase2/tests -resultBundlePath /tmp/habitsquares-phase2/final.xcresult -parallel-testing-enabled NO test
xcodebuild -project habitSqaures.xcodeproj -scheme 'Habit Tracker' -destination 'platform=iOS Simulator,id=02F1EF02-1EAC-456D-B953-FB4D674D3538' -derivedDataPath /tmp/habitsquares-phase2/tests -resultBundlePath /tmp/habitsquares-phase2/batched-history.xcresult -parallel-testing-enabled NO -only-testing:habitSqauresTests test
xcodebuild -project habitSqaures.xcodeproj -scheme 'Habit Tracker' -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/habitsquares-phase2/device build
```

The dedicated simulator is **HabitSquares Phase 2 Tests**, iPhone 17 Pro, iOS 27.2. Toolchain: Xcode 27.2 (27B52). Full suite log: `/tmp/habitsquares-phase2-tests-final.log`; post-batch regression log: `/tmp/habitsquares-phase2-tests-batched.log`; final Release log: `/tmp/habitsquares-phase2-release-batched.log`. Result bundles are under `/tmp/habitsquares-phase2/`; temporary build evidence may be cleaned by macOS.

No personal-device store was opened for testing, no personal app was uninstalled, no data reset or schema migration was performed, no identifiers changed, no CloudKit capability was added, and no Apple upload, archive export or publishing was performed. This branch contains the approved fixes and validation report; physical-device release gates remain outstanding.
