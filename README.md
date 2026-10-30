# SixOne

**English · [简体中文](README.zh-Hans.md)**

A macOS menu-bar clipboard history tool. A global hotkey (default `⌃⌘V`) opens a floating panel where you can browse, search, preview, edit in place, and paste history entries back. Five content kinds: **text / image / file (including multi-file groups) / link / colour**.

What it does:

- Click the menu-bar icon to toggle the panel, or right-click it for a menu (Open Clipboard / Settings / Quit SixOne). The panel is anchored to wherever the summon came from — under the status item, under the pointer, or centred on the screen.
- Native search field: filters across body text, titles, and file paths, debounced 200 ms before the query reaches the database.
- Previews: text (rich text, editable in place, `⌘F` find), image (zoom / pan), file (image / video / web page / PDF / text / Quick Look), multi-file list (filter by file name / path), link, colour. File and on-disk image previews show the source path at the bottom; drag to select part of it or copy the full path in one click, and the file name is copyable too.
- Item actions: copy back to the clipboard, paste into the previous app (synthesizes `⌘V`), share, open with the default app / reveal in Finder, delete, and copy or paste as plain text (`⇧⌘C` / `⇧⌘V`). If the previous app has quit or does not come forward, SixOne beeps and leaves the item on the clipboard rather than pasting into whatever is frontmost.
- Settings: privacy ignore-list, history retention, global hotkey, language (Follow System / English / Chinese (Simplified)), launch at login, and clear-history. A language change takes effect after a restart.

## Screenshots

A short clip: open the panel, preview and zoom an image, copy its source path, then search the list:

![SixOne: open the panel, preview and zoom an image, copy its path, and search](docs/images/demo.gif)

| Panel | Search | Preview | Settings |
| --- | --- | --- | --- |
| <a href="docs/images/panel.jpg"><img src="docs/images/panel.jpg" alt="The panel listing text, image, and file entries" width="180"></a> | <a href="docs/images/panel-search.jpg"><img src="docs/images/panel-search.jpg" alt="The search field filtering the list" width="180"></a> | <a href="docs/images/preview.jpg"><img src="docs/images/preview.jpg" alt="An image previewed in the panel" width="180"></a> | <a href="docs/images/settings.jpg"><img src="docs/images/settings.jpg" alt="The Settings window: General pane with launch-at-login, language, and the Accessibility permission" width="180"></a> |

## Status

**1.0.0, source release.** No prebuilt binaries — you build from source. The store is versioned (currently schema **V3**) and opened through `SixOneMigrationPlan`; upgrading from V1 migrates the existing store in place, so a schema change no longer requires clearing history. Migration is forward-only: back up the store before downgrading to an older build.

**Non-goals:** cloud sync, accounts, multi-device history, an iOS client, auto-update. SixOne is deliberately a local-only, single-Mac tool.

## Requirements

- **macOS 26.5 or later on Apple silicon.** Deployment target 26.5; the documented build command targets `arm64`.
- **Xcode 27.1 (27A9275) with Swift 6.4** is what this project is verified against; another Xcode that still ships a ≥ 26.5 SDK may work, but nothing else is tested.
- The command-line build needs no developer certificate (`CODE_SIGNING_ALLOWED=NO`). The Xcode build uses the team recorded in the project; contributors should set `DEVELOPMENT_TEAM` to their own in Signing & Capabilities.

## Privacy and data

Clipboard history is among the most sensitive data on a Mac, so the rules are stated in full in **[PRIVACY.md](PRIVACY.md)**. The short version:

- **Everything stays on this Mac.** No telemetry, no accounts, no cloud sync, no auto-update, no third-party SDKs. History lives in a SwiftData store at `~/Library/Application Support/SixOne/SixOne.store` — a path whose name belongs to this app alone — inside the sandbox container when the app is signed with its entitlements.
- **Two filters decide what gets recorded, and both run *before* any clipboard bytes are read:** the do-not-record pasteboard markers that password managers set, and an ignore-list of source apps you control (Passwords and Keychain Access are pre-ignored). The marker check is the one that matters — see §1 of PRIVACY.md for why a source-app rule alone is not enough.
- **Nothing is encrypted at rest** beyond the container's own permissions and FileVault.
- **The only network-capable component is the HTML preview, and it is fenced:** no content scripts, no navigation away from the local file, and the remote channels that could carry data away (`document`, `script`, `raw`, `popup`) are blocked. Remote images and stylesheets are deliberately allowed so a saved page renders instead of showing broken images; the residual cost is that a remote image request reveals your IP, the way any tracking pixel does.
- **Accessibility permission is used for exactly one thing**: synthesizing a single `⌘V` into the app you were using before the panel opened. The app never reads other apps' UI.

## Keyboard shortcuts

| Action | Key |
| --- | --- |
| Open / close the panel | `⌃⌘V` (configurable in Settings) |
| Search | `⌥⌘F` (or `⌘F` in the list); `Esc` clears, `Esc` again leaves the field |
| Move selection | `↑` / `↓` (with nothing selected, `↓` lands on the first row and `↑` does nothing); `⌘↑` / `⌘↓` jump to the newest / oldest in the window |
| Back to the search field | `↑` from the first row |
| Paste into the previous app | `Return` (or `⌘V`) |
| Quick-paste a visible row | Hold `⌘` to show numbers, then press `⌘1`…`⌘9` to paste a fully visible row (in a file-group overview it pastes the group file; `⇧` makes it plain text in the outer list) |
| Copy back to the clipboard | `⌘C` |
| Save edits | `⌘S` (editing only; stays in edit mode; `Return` still inserts a newline) |
| Copy / paste as plain text | `⇧⌘C` / `⇧⌘V` |
| Toggle preview | `Space` |
| Step through items while previewing | `↑` / `↓` (file groups open only from the list: stepping onto one keeps the current preview and shows a hint) |
| Group list | `↑` / `↓` move only inside the group (with nothing selected `↓` lands on the first row and `↑` does nothing; `↑` from the first row returns to the filter field, `↓` at the last row stops); `⌘↑` / `⌘↓` jump to the first / last file; `Space` previews the selected file (or closes the group preview when nothing is selected); `Esc` closes the group preview |
| Group file preview | `↑` / `↓` switch to the previous / next file; `⌘↑` / `⌘↓` jump to the first / last file; `Space` / `Esc` / `×` return to the group list |
| Filter files in a group | The filter field in the group list header (`⌘F` focuses it; `Esc` clears, then exits the field) |
| Delete the selected item | `⌫` / `⌘⌫` / `⌦` (asks for confirmation) |
| Open / reveal in Finder | `⌘O` / `⇧⌘R` |
| Cancel editing, close preview, then the panel | `Esc` (layered — it closes the find bar, cancels editing and restores the original text, asks first if there are changes, then closes the preview) |
| Cycle search field → more actions → list | `Tab` / `⇧Tab` (also `Control+Tab` / `Control+Shift+Tab`) |
| Close the panel / quit / settings | `⌘W` / `⌘Q` / `⌘,` (while editing, both cancel editing and ask first if there are changes; press again to close the panel / quit) |

The panel maintains its own Tab loop because the AppKit controls and the list have no usable system key view loop. With Full Keyboard Access on it visits search field → more actions → list; with it off it visits search field ↔ list, matching the system default. `Control+Tab` / `Control+Shift+Tab` use the same loop.

The main menu is not displayed in this menu bar app; it serves as a key-equivalent command table (`File` provides `⌘S` / `⌘W`, `Edit` / `Item` provide editing and item commands). `About SixOne`, `Settings`, and `Quit` live in the status bar menu. When the menu bar is unavailable (the panel is nonactivating, so the menu bar may still belong to the previous app), a window-level fallback looks up the same menu item by key equivalent, re-runs menu validation, and sends its action, keeping keyboard behavior consistent with the menu.

## Quick start

```bash
# Build (unsigned; no developer certificate required)
xcodebuild build -project SixOne.xcodeproj -scheme SixOne \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# Unit tests
xcodebuild test -project SixOne.xcodeproj -scheme SixOne \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# Run — after the build step: `build/` is gitignored and absent in a fresh clone
open build/Build/Products/Debug/SixOne.app
```

The app is in the Swift 6 language mode (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) and uses newer APIs such as `NSGlassEffectView`.

The tests genuinely launch the XCTest host (`TEST_HOST` is `SixOne.app`), which needs a normal window session and a pty. Running the `test` action in a container or a restricted sandbox fails during process setup; building is unaffected.

## First run

**After `open …` nothing appears to happen — that is expected.** SixOne is a menu-bar app (`LSUIElement`), so there is no Dock icon and no window. Look for the clipboard icon in the menu bar, or press `⌃⌘V`.

The first time you press `Return` (or double-click) to paste into another app, macOS asks for **Accessibility** permission: System Settings → Privacy & Security → Accessibility → enable SixOne. Until it is granted, the panel says so rather than failing silently.

The command-line build above is unsigned *and unsandboxed*: `CODE_SIGNING_ALLOWED=NO` also drops the entitlements, including the App Sandbox, and the store then lives in the user-level Application Support directory rather than a container. Build and run from Xcode (⌘R) for the sandboxed configuration.

## Architecture

The code is layered one-way by "who depends on whom": a higher layer may depend on a lower one, never the reverse. The entry layer (`SixOneApp` / `AppDelegate` / `AppComposition` / `PanelAssembly`) wires up the UI (`UI/`, `Views/`), which sits on the managers (`Managers/`), which sit on the pasteboard and persistence layers, with business-agnostic helpers in `Support/`. `AppComposition` is the composition root: it builds the data layer, the panel, and the global hotkey, and connects them, which is why it can be exercised without an `NSApplication`.

Data flows one way, over one bus: an `NSPasteboard` change is parsed off the main thread, de-duplicated, inserted, and posted on `ClipboardHistoryEventBus`; `HistoryListStore` then refreshes incrementally. Reads go through `ClipboardHistoryRepository` on a background actor and come back as lightweight `HistoryRow` values, so large fields never enter list memory; writes go through the main context and are immediately visible to reads. Every UI action — copy, paste, save an edit, delete, clear — flows back over that same bus, so the list never has to know who changed the data.

The two former god objects are split by responsibility: `ClipboardManager` is a façade over capture, history writes, pasteboard writes, file access, and thumbnails; `ClipboardPanelController` delegates to `PanelWindowLifecycle`, `PanelItemActions`, `PanelEditingSession`, and `PanelKeyActionExecutor`. The two NSTableView-based lists share `ListTableCoordinator` and `ListTableScaffold`; each list only supplies rows, row content, selection, and its scroll policy. Views emit copy/save intents through `PanelContext.copyItem` / `copyText` / `saveEditedText`, backed by `PanelActionHandler`; they treat the manager as read-only.

**Comments are deliberately terse**: they state the constraint that still matters, not the history behind it. The tests are the executable contract — the table below points to the suite that pins each area — so read the type and its tests before changing a non-obvious rule.

## Where to look when changing code

| What to change | Where it goes |
| --- | --- |
| Add / change a key branch | `PanelKeyRouter` (window pre-dispatch) + `PanelKeyActionExecutor` for routed actions; item commands live in `PanelItemActions`, editing/escape in `PanelEditingSession`; command keys come from `MenuKeyEquivalentIndex`. Tests: `PanelKeyRouterTests` / `PanelWindowKeyHandlingTests` / `MenuKeyEquivalentIndexTests` |
| Add a "should the panel hide" rule | `PanelFocusPolicy` + `PanelFocusPolicyTests` |
| Touch panel activation / image-preview pinch gestures / status-item click behaviour | Gesture events only reach the **active** app, so summoning the panel must make it key and main, and hiding must take the Settings window out of the key/main candidate set. See `PanelWindowLifecycle` and `SettingsWindowPresentationTests` for the key/main hand-off rules |
| Change the query pipeline (debounce / clear / reveal alignment) | `PanelSearchSession` + `PanelSearchSessionTests`; the top bar only hands in "the input changed" |
| Add a context-menu item | `ItemCommand` (title, shortcut, layout) + `ItemCommandTests`, with behavior in `RowMenuBuilder` / `FileGroupPreview` |
| Add a view-side action (copy, save an edit, copy text) | Emit an intent through `PanelContext.copyItem` / `copyText` / `saveEditedText`, backed by `PanelActionHandler`; do not call `ClipboardManager` mutators from views. Tests: `RowMenuBuilderTests` / `TextPreviewFormattingTests` / `LinkPreviewInteractionTests` |
| Add a setting | `SettingsStore` (persistence port is `SettingsStorage`) + the matching pane file (`Views/Settings/*SettingsView.swift`) |
| Change the global hotkey (registration / key events) | `HotKeyManager` + two ports: `HotKeyRegistering` (registration, can fail) / `HotKeyEventMonitoring` (key events, dispatched per instance) + `HotKeyManagerTests` |
| Add / change a model field | Copy `Persistence/Schema/SixOneSchemaV3.swift` into a new `SixOneSchemaV<N>` (never edit a frozen version), add a `MigrationStage` to `SixOneMigrationPlan`, then point the `ClipboardItem` typealias at the new version. Shape changes and `#Index` additions reach existing stores through the plan. Tests: `SchemaMigrationTests` / `SchemaIndexTests` |
| Change a fetch path | First decide "need the whole item" vs "only identity/paths": `ClipboardManager.fetchFullItem` / `ClipboardManager.fetchLightItem`. The list window is a different path — `ClipboardHistoryRepository.latest` on the background actor |
| Change where the store lives, or the "won't open → rename aside and rebuild" fallback | `AppModelContainer` + the `历史库位置与兜底` suite. The store must keep its own file name: the fallback may only ever touch this app's own file |
| Change how a file is reached after the fact (moved, renamed, or after a restart) | `SecurityScopedFileAccess`: bookmark first, original path as fallback, at most 100 bookmarks per copy. Covered by `ItemOpenabilityTests` / `PreviewLauncherTests` / `FileGroupPreviewModelTests` |
| Change what counts as "do not record" | `PasteboardSnapshot.doNotRecordTypes` + `ClipboardCaptureTests`; the check must stay *before* the snapshot is read |
| Change paste-into-another-app | `PanelPasteFlow` + `PanelPasteEnvironment` (event poster, app controller, permission, scheduler, clock, feedback). The `⌘V` event must be proven creatable *before* the clipboard is touched, because notices are invisible once the panel hides. Tests: `PanelPasteFlowTests` |
| Change the sort key / touch `recencyID` | `OrderedUUID` (time ordering) + `OrderedUUIDTests`; sorting is by this column descending, and generation order must match comparison order |
| Change text-file encoding detection | `TextFileReader` (BOM → UTF-8 → GB18030 → Latin-1) + `TextFileReaderTests` |
| Change list selection movement / preview follow | `PanelSelectionCursor` (a failed preview switch must roll back) + `PanelSelectionCursorTests` |
| Change the list container / scroll feel / visible range | `ListTableCoordinator` / `ListTableScaffold` hold the shared NSTableView machinery; `HistoryListTableView` and `GroupListTableView` only supply rows, row content and selection. Shared primitives live in `ListRowPrimitives` / `HistoryListScrollGeometry`. Tests: `ClipboardVisibleRangeTests` / `ClipboardScrollerFlashTests` / `HistoryListScrollTests` / `HistoryListRowViewReuseTests` / `GroupListTableViewTests` |
| Change share | `PanelSharing`; the panel side only hands in the anchor and "hide the panel" |
| Change assembly (who wires to whom) | `AppComposition` / `PanelAssembly`, plus a wiring test (`AppCompositionTests`) |
| Add a localized string | Use `Localizer.string(...)` / `LocalizedStringKey` in code, and add the entry to `Localizable.xcstrings` (English is the source language; add `zh-Hans`) |
| Change tooltips / hover labels | `.appTooltip` (`TooltipAnchor`) + `TooltipPresenter`; positioning tests in `TooltipPresenterTests` |

## Testing

The test target is `SixOneTests`, written with [swift-testing](https://github.com/apple/swift-testing); the command is in **Quick start**. It is 589 tests in 95 suites, about 11 seconds (swift-testing's own count; `xcresulttool` counts parameterized cases separately). The test host runs in the same process as the real app (`TEST_HOST` = `SixOne.app`), so `AppDelegate.isRunningUnitTests` switches the process to an in-memory store and skips monitoring, the hotkey, and the status bar; `TestHostTests` is the sentinel that guards that check.

Modules that touch system resources are driven by doubles, all under `SixOneTests/Support/`: the clipboard goes through `FakePasteboard` (so capture → dedup → touch-to-top is testable without overwriting your clipboard), settings and the hotkey through `InMemorySettingsStorage`, the hotkey event handler through `FakeHotKeyEventMonitor`, history reads through `FakeHistoryRepository`, offscreen windows and view-tree probes through `OffscreenHost` and `TestPanel`, temporary files through `TemporaryFiles`, and waiting through `Wait`. Preview, positioning, keyboard decisions, and focus policy are pure functions or pure value inputs. The performance benchmark in `HistoryBenchmarkTests` is skipped unless a switch file exists (`.benchmark-history` at the repo root, or `/tmp/sixone-benchmark`); do not leave either behind, as it slows the full suite down.

## Contributing

Contributions are welcome. The build and test commands are under **Quick start**, and the "Where to look when changing code" table is the fastest way to find the right file.

### Privacy invariants — do not regress these

Each exists because of a specific failure. A change that weakens one has to say so and show how it still holds.

1. **Do-not-record markers are checked before the clipboard is read** (`PasteboardSnapshot.doNotRecordTypes`, consulted before `PasteboardAccessing.snapshot`). A source-app ignore list exists too, but it cannot replace this one — the frontmost app is not reliably the app that wrote the content.
2. **The store keeps its own file name.** `AppModelContainer` must never fall back to SwiftData's default `Application Support/default.store`, and the "won't open → rename it aside and rebuild" fallback may only touch `SixOne.store` — otherwise it acts on another app's database.
3. **The HTML preview stays fenced.** No content JavaScript, no navigation away from local files, and the remote content-transfer channels stay blocked (`document`, `script`, `raw`, `popup`). Remote images, stylesheets, and fonts are deliberately allowed — see [PRIVACY.md](PRIVACY.md) §3 before changing the rule.
4. **The paste path fails before it changes anything.** `PanelPasteFlow` proves a `⌘V` event can be created *before* writing the clipboard or hiding the panel, because a notice is invisible once the panel is gone.
5. **Logs stay at the default privacy level.** Never interpolate clipboard text or file paths into `os.Logger` with `privacy: .public`.

### Conventions

- **Language.** `README` and `PRIVACY` ship in both English and Chinese; keep the `.zh-Hans.md` side in sync in the same PR. Code comments, `@Suite` / `@Test` display names, and commit messages are Chinese. (Translating test display names to English is welcome: it changes no logic, and they are what an outside contributor reads when a test fails.)
- **Keyboard decisions stay pure.** `PanelKeyRouter.route(_:context:)` and `PanelFocusPolicy.shouldHide(_:)` take a snapshot and return a value, never touch a window; a new branch needs a new row in the matching test file.
- **New user-visible text** goes through `Localizer.string(...)` or a `LocalizedStringKey` **and** into `Localizable.xcstrings` with a `zh-Hans` value. `LocalizationCoverageTests` catches a literal key with no entry; it cannot see a key you never added.
- **Tests never touch the real system** — `FakePasteboard`, `InMemorySettingsStorage`, `FakeHistoryRepository`, `OffscreenHost`, `TemporaryFiles` — and they poll with `Wait.until` rather than `sleep`.

For a security or privacy issue, please use GitHub's private reporting (**Security** tab → *Report a vulnerability*) rather than a public issue. Details, and what to include, are in [PRIVACY.md](PRIVACY.md) §7.

## Acknowledgements

Built with [swift-testing](https://github.com/apple/swift-testing) (Apache-2.0 with the Swift Runtime Library Exception) for the test suite. Everything else is Apple's own frameworks: AppKit, SwiftUI, SwiftData, WebKit, Quick Look, and ServiceManagement.

## License

[MIT](LICENSE).
