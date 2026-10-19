# Contributing to Light CRM

Use macOS 27+ and Xcode 27+. Open the existing project and shared Light CRM scheme; do not create another app target. The root Swift package is a test harness, not a second app.

## Development workflow

1. Start a focused branch. Explain the user-facing problem and keep scope small.
2. Use your own signing team locally or the unsigned build command in README. Do not commit credentials, signing profiles, personal scheme state, or team changes needed only on your machine.
3. Preserve offline behavior, accessibility, stable record IDs, and explicit save/rollback semantics. Do not add a service or dependency without discussing its need and license.
4. Add focused tests when storage, relationship, date, monetary, import, or backup behavior changes. A new backup version needs explicit compatibility handling; never silently accept incompatible data.
5. Run the checks below and describe exactly what passed in your pull request. Include fictional-data screenshots for UI changes.

```sh
xcodebuild build -project 'Light CRM.xcodeproj' -scheme 'Light CRM' \
  -destination 'platform=macOS' -derivedDataPath /tmp/LightCRMBuild \
  CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM=
swift test --scratch-path /tmp/LightCRMTests
python3 scripts/check-contrast.py
git diff --check
```

The test suite uses unique temporary directories, not your actual workspace. It tests database reopen, stage persistence, relationship deletion, cascade metadata cleanup, civil dates, exact decimal addition, duplicate filenames, failed imports, backup round trips, independent-workspace restores, safety backups, injected restore failures, corruption/unsupported versions, missing files, symlinks, and traversal paths. The optional injected failure callback is internal and is not exposed by the app.

## Manual QA

- Empty workspace: no automatic sample insertion. Explicit sample action works once.
- Create/edit each kind, cancel dirty edits, cancel window close/quit with unsaved edits, verify empty-name and invalid-money feedback.
- Command-N chooses the current section; Command-F focuses search; Tab/Shift-Tab and arrow keys work; selection/focus remain visible. Exercise VoiceOver labels and the non-drag stage menu.
- Search long names/notes, sort table columns (including numeric value), filter stages, select board cards, change stage by menu and drag, switch to table, quit and reopen.
- Complete/reopen tasks; check upcoming, overdue, completed, and no-date cases. Check civil dates around DST and after changing a test machine's time zone.
- Link contacts/companies/deals/tasks. Confirm deletion warnings; remaining work must survive and become unlinked.
- Import two files with the same display name; open and reveal them. Try folders, aliases, missing originals, unreadable files, and large files. Cancel native file panels. Confirm that managed deletion leaves originals unchanged.
- Export to a chosen folder, restore into a disposable workspace, and verify relationships/documents/currency. Verify the safety backup. Test missing/corrupt files and an unwritable/full volume; failure must preserve existing data.
- Inspect at 960×620 and larger, with inspector shown/hidden and a horizontally scrolled board. Check Light/Dark/System appearance, Reduce Motion, Reduce Transparency, long names, empty notes, and missing relationships.

`Design.swift` centralizes colors and typography. The contrast script checks 38 small-text pairs, including the white-on-blue primary action. Motion is brief and disabled when Reduce Motion is enabled; app surfaces are opaque. Native controls/window chrome may retain platform styling.

## Repository hygiene

Never include real clients or their documents in tests, screenshots, issues, or PRs. Keep build output and test fixtures containing local data outside source control. Font updates must preserve the license and update the source/checksum notice. Do not upload a workspace backup as a bug report.

GitHub Actions uses a hosted Xcode 27 runner and no signing secrets. Local success does not establish that a workflow has run remotely. Record toolchain and OS versions when reporting a failure.
