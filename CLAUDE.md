# cmux agent notes

> This file is agent-operating-config per `ops-layer standards/claude-md-scope.md`.
> Full build/test/release reference + upstream-sync policy: knowledge note `301b654c-9604-461e-8125-ea627a3f18b1`.

## Local dev — essential build rule

After making code changes, always run the reload script with a tag:

```bash
./scripts/reload.sh --tag <your-branch-slug>
```

**Never run bare `xcodebuild` or `open` an untagged `cmux DEV.app`.** Untagged builds share the default debug socket and bundle ID with other agents, causing conflicts and focus theft.

Compile-only check (no launch, no socket conflicts):

```bash
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-<your-tag> build
```

Other reload variants (`reloadp`, `reloads`, `reload2`, `dogfood-release.sh`) and full detail on app-path cmd-click links, tagged CLI dogfood, and debug log paths are in knowledge note `301b654c`.

## Testing policy

**Never run tests locally.** All tests (E2E, UI, Python socket tests) run via GitHub Actions or on the VM.

- **E2E / UI tests:** trigger via `gh workflow run test-e2e.yml`
- **Unit tests:** `xcodebuild -scheme cmux-unit` is safe (no app launch), but prefer CI
- **Python socket tests (`tests_v2/`):** CI only; if local, use a tagged build's socket: `CMUX_SOCKET_PATH=/tmp/cmux-debug-<tag>.sock`
- **Never `open` an untagged `cmux DEV.app`** from DerivedData — conflicts with the user's running debug instance.

## Regression test commit policy

When adding a regression test for a bug fix, use a two-commit structure:

1. **Commit 1:** Add the failing test only (no fix). CI goes red.
2. **Commit 2:** Add the fix. CI goes green.

This proves the test genuinely catches the bug in the GitHub PR UI.

## Test quality policy

- Do not add tests that only verify source code text, method signatures, AST fragments, or grep-style patterns.
- Do not add tests that read checked-in metadata (`Info.plist`, `project.pbxproj`, `.xcconfig`) only to assert that a key or snippet exists.
- Tests must verify observable runtime behavior through executable paths (unit/integration/e2e/CLI).
- For metadata changes, prefer verifying the built app bundle or the runtime behavior that depends on that metadata.
- If no meaningful behavioral test is practical, skip the fake regression test and state that explicitly.

## Socket command threading policy

- Do NOT use `DispatchQueue.main.sync` for high-frequency socket telemetry commands (`report_*`, `ports_kick`, status/progress/log metadata updates).
- Hot-path telemetry: parse/validate off-main → dedupe/coalesce off-main → `DispatchQueue.main.async` only for minimal UI mutation.
- Commands manipulating AppKit/Ghostty UI state directly (focus/select/open/close/send key, list/current snapshot queries) may run on main actor.
- New socket commands default to off-main; require explicit code comment when main-thread execution is necessary.

## Socket focus policy

- Socket/CLI commands must NOT steal macOS app focus (no app activation or window raising side effects).
- Only explicit focus-intent commands may mutate in-app focus/selection (`window.focus`, `workspace.select/*`, `surface.focus`, `pane.focus/last`, browser focus commands, v1 focus equivalents).
- All non-focus commands preserve current user focus context.

## Shared behavior policy

- When a behavior is exposed through multiple entrypoints (keyboard shortcut, command palette, context menu, CLI, settings, debug menu), implement one shared action/model path and verify every entrypoint. Do not patch one surface while leaving others with duplicated logic.
- Optimistic UI/CLI: one mutation path, pending state with request id or previous snapshot, reconcile from authoritative result, explicit rollback on failure.
- When tests missed a bug, add behavior-level coverage around the exact repro path before claiming the fix is complete.

## Debug menu

The app has a **Debug** menu in the macOS menu bar (DEBUG builds only). Use it for visual iteration:

- **Debug > Debug Windows** contains panels for tuning layout, colors, and behavior. Entries are alphabetical with no dividers.
- To add a debug toggle: create an `NSWindowController` subclass with a `shared` singleton, add it to "Debug Windows" in `Sources/cmuxApp.swift`, add a SwiftUI view with `@AppStorage` bindings.
- When the user says "debug menu" or "debug window", they mean this menu, not `defaults write`.

## Pitfalls

- **Custom UTTypes** for drag-and-drop must be declared in `Resources/Info.plist` under `UTExportedTypeDeclarations` (e.g. `com.splittabbar.tabtransfer`, `com.cmux.sidebar-tab-reorder`).
- Do not add an app-level display link or manual `ghostty_surface_draw` loop; rely on Ghostty wakeups/renderer to avoid typing lag.
- **Typing-latency-sensitive paths** (read carefully before touching these areas):
  - `WindowTerminalHostView.hitTest()` in `TerminalWindowPortal.swift`: called on every event including keyboard. All divider/sidebar/drag routing is gated to pointer events only. Do not add work outside the `isPointerEvent` guard.
  - `TabItemView` in `ContentView.swift`: uses `Equatable` conformance + `.equatable()` to skip body re-evaluation during typing. Do not add `@EnvironmentObject`, `@ObservedObject` (besides `tab`), or `@Binding` properties without updating the `==` function. Do not remove `.equatable()` from the ForEach call site. Do not read `tabManager` or `notificationStore` in the body; use the precomputed `let` parameters instead.
  - `TerminalSurface.forceRefresh()` in `GhosttyTerminalView.swift`: called on every keystroke. Do not add allocations, file I/O, or formatting here.
- **Terminal find layering contract:** `SurfaceSearchOverlay` must be mounted from `GhosttySurfaceScrollView` in `Sources/GhosttyTerminalView.swift` (AppKit portal layer), not from SwiftUI panel containers such as `Sources/Panels/TerminalPanelView.swift`. Portal-hosted terminal views can sit above SwiftUI during split/workspace churn.
- **Submodule safety:** When modifying a submodule (ghostty, vendor/bonsplit, etc.), always push the submodule commit to its remote `main` branch BEFORE committing the updated pointer in the parent repo. Never commit on a detached HEAD or temporary branch — the commit will be orphaned. Verify with: `cd <submodule> && git merge-base --is-ancestor HEAD origin/main`.
- **All user-facing strings must be localized.** Use `String(localized: "key.name", defaultValue: "English text")` for every string shown in the UI. Keys go in `Resources/Localizable.xcstrings` with translations for all supported languages (currently English and Japanese). Never use bare string literals in SwiftUI `Text()`, `Button()`, alert titles, etc.
- **Shortcut policy:** Every new cmux-owned keyboard shortcut must be added to `KeyboardShortcutSettings`, visible/editable in Settings, supported in `~/.config/cmux/cmux.json`, and documented in the keyboard shortcut and configuration docs.
- **Snapshot boundary for list subtrees.** In any SwiftUI panel whose `body` contains a `LazyVStack` / `LazyHStack` / `List` / `ForEach` of rows, no view below that boundary may hold a reference to an `ObservableObject` / `@Observable` store (no `@ObservedObject`, `@EnvironmentObject`, `@StateObject`, `@Bindable`, or even a plain `let store: SomeStore` property). Rows and drop-gaps receive immutable value snapshots plus closure action bundles only. Violating this reintroduces the "orthogonal @Published change invalidates every row and thrashes `LazyLayoutViewCache`" class of 100% CPU spin loop that hit the Sessions panel and the workspace sidebar (https://github.com/manaflow-ai/cmux/issues/2586). Reference pattern: `IndexSectionActions` / `SectionGapActions` / `SessionSearchFn` in `Sources/SessionIndexView.swift`.
- **No state mutation inside view-body computations.** A function called from `body` (directly or through a helper) must not write `@Published` state, schedule a `Task { @MainActor in store.x = … }`, or `DispatchQueue.main.async` a store write. That creates a re-render feedback loop and pegs the main thread. State-changing work belongs in a `reload()` completion, a `didSet`, or a property observer — never in the projection that feeds `ForEach`.
- **Foundation, SwiftUI, AttributeGraph, and WebKit semantics change silently between macOS major versions.** A function that "obviously" returns the same value on every macOS is not a reliable assumption. Concrete case (issue #4529): `URL(fileURLWithPath: "/").deletingLastPathComponent().path` returns `"/.."` on macOS 14 and 15 but `"/"` on macOS 26 — Apple silently fixed the underlying CFURL normalization. Always test on the reporter's macOS before declaring a user-reported repro disproven. AWS M4 Pro builders (`cmux-aws-mac`, `cmux-aws-m4pro`, `aws-m4pro-1..6`) are pre-provisioned on macOS 15.7.4 and the preferred empirical-repro path.
- **Test files in `cmuxTests/` must be wired into `cmux.xcodeproj/project.pbxproj`.** A `.swift` file added without a matching `PBXFileReference` + `PBXSourcesBuildPhase` entry is silently ignored — Xcode and CI report "Executed 0 tests" with no error. The `workflow-guard-tests` job runs `./scripts/lint-pbxproj-test-wiring.sh` to catch this at PR time. Add via Xcode (drag into the cmuxTests target) or hand-edit the four pbxproj entries; use `TabManagerUnitTests.swift` as a reference sibling.
