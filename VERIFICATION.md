# Verification record

Local checks performed on 2026-10-18 using macOS 27.0.1 and Xcode 27.0 (27A266a), Apple Silicon.

## Automated checks actually run

- Existing Light CRM macOS target built with the shared scheme, `CODE_SIGNING_ALLOWED=NO`, and `DEVELOPMENT_TEAM=`. This does not verify signing/notarization.
- `swift test`: **11 XCTest tests passed, zero failures**. Tests compile the actual Models/Storage source files using the root Swift package.
- `python3 scripts/check-contrast.py`: **38 text/surface pairs passed**, minimum 4.79:1.
- `git diff --check`: passed.

The storage tests cover database reopen and stage persistence; company/contact/deal deletion preserving linked work; attachment metadata cascade and managed-file cleanup; original-file preservation; duplicate filenames; failed import/copy; decimal arithmetic; civil-day validity; complete backup round trips and safety copies; restoration into a different workspace; an injected transaction failure preserving existing data/files; corrupt and unsupported backups; missing documents; invalid relationship IDs; duplicate IDs; traversal paths; and symbolic links.

The initial sandboxed build/test attempts were blocked by compiler plugin/cache permissions. The successful checks ran with permission outside that sandbox. Xcode emitted its standard notice that App Intents metadata extraction was skipped because the app does not use AppIntents; there were no Swift compilation errors in the successful build.

## Live UI checks actually performed

- Launched the built app with an empty workspace; no automatic seed occurred.
- Explicitly loaded fictional sample data and verified overview totals.
- Followed an overview link into a selected deal's inspector.
- Edited and saved the deal's next action; the inspector reflected the change.
- Used a board card's accessible stage menu; the card moved to Awaiting commitment, and the table showed the same stage.
- Used Command-F and filtered the deals table.
- Completed a task from Overview and verified it in the Completed task view.
- Quit and relaunched; the sample records, changed next action, stage, and completion remained saved.
- Inspected the empty dark overview and populated light overview/editor visually; verified visible input focus and validation for an empty required name.
- Used Command-N in Contacts and verified a contact editor opened. Changed its draft, cancelled, observed the discard confirmation, and discarded only that unsaved verification draft.
- Imported a fictional local text document using the native file panel; the inspector displayed its original filename, 71-byte size, and added date. The open action launched TextEdit, but the automation service timed out while inspecting TextEdit's contents.

Fictional sample records and the verification document were left in the local test workspace, not the repository. The source text document was created in the system temporary directory. No real client data was used.

## Not claimed as verified

- Full VoiceOver traversal, all keyboard-only interactions, native quit/window-close confirmation, and accessibility preference combinations.
- Actual board/file drag gestures, Reveal in Finder, every external document type, large-file performance, and full-disk/permission failure UI behavior.
- Exhaustive window-size, multi-monitor, localization, or time-zone changes in the running GUI. Date and money rules have focused automated coverage.
- Backup/restore through every native panel path; database/filesystem round trips and failures were tested directly against the same storage services.
- App Store/distribution signing, notarization, Intel execution, or earlier macOS releases.
- GitHub Actions execution: the workflow is prepared, but no repository was created or pushed and no remote CI run occurred.

Use the manual checklist in CONTRIBUTING.md before declaring a public release. The final app icon, explicit hover/focus refinements, and default task date sorting were compilation-checked after the live UI session; they were not separately re-reviewed visually.
