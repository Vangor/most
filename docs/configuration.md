# most.json settings

Global app preferences live in `~/.config/most/most.json`.

On first launch, `most` migrates an existing `~/.config/cmux/` directory by copying its contents into `~/.config/most/` (renaming `cmux.json` to `most.json`). The legacy directory is left in place as a fallback. A marker file `~/.config/most/.migrated-from-cmux` ensures the migration runs only once.

## `app.confirmQuit`

Controls when most asks before quitting:

- `always`: show the quit confirmation on Cmd+Q or app quit.
- `dirty-only`: show it only when a workspace has a terminal or panel that reports close confirmation is needed.
- `never`: quit immediately.

Default: `always` for stable and nightly builds. DEV builds always behave as `never`, regardless of the file setting, so tagged development builds can be replaced without a full-screen quit dialog.

The older boolean `app.warnBeforeQuit` still works as a fallback when `app.confirmQuit` is not set. `true` maps to `always`; `false` maps to `never`.

## Themes

most ships a curated set of Ghostty-format themes in `Resources/ghostty/themes/`. The default for fresh dark installs is `p-dev` — a warm-dark cyan-led palette designed for the studio. Light defaults to `Apple System Colors Light`.

Switch themes in `most.json`:

```json
{
  "terminal": {
    "theme": "p-dev"
  }
}
```

Existing users keep their selected theme on upgrade — the default flip only applies to fresh installs (no prior `theme` key in `most.json`).

### How the palette repaints existing output (Claude colors)

Ghostty maps the standard 16 ANSI slots through the active palette in real time, so most CLI output (including Claude CLI's banners, prompts, tool labels, and code highlights when ANSI mode is active) repaints automatically when you switch themes. No re-render needed.

- **~80–90% of Claude CLI chrome** uses ANSI escapes → repaints through the palette.
- **24-bit truecolor surfaces** (Claude's status bar, some syntax highlight blocks) bypass the palette and render their hardcoded RGB values regardless of theme.
- If Claude exposes a 16-color mode, setting `CLAUDE_FORCE_ANSI=1` in the shell environment forces it back through ANSI so palette overrides reach the chrome.

## URL scheme handlers

most claims two URL schemes via macOS LaunchServices:

- **`ssh://`** — standard SSH URLs. Clicking `ssh://user@host:port/path` anywhere on macOS opens a new most tab connected to the host. Trailing `/path` is preserved on the request but not yet plumbed to a CLI working-directory argument; it currently renders only in the launch confirmation dialog. Add `?fragment=<name>` to set the session/tab title.
- **`cmux://`** — the upstream query-param variant (`cmux://ssh?host=…&user=…&port=…&title=…&no-focus=true`) for fine-grained control. See `Sources/CmuxSSHURLRequest.swift` for the full parameter list (host, user, port, title/name, connect-timeout, server-alive-interval, server-alive-count-max, host-key-policy, no-focus).

Both schemes route through the same confirmation flow and CLI launcher, so the SSH validation rules (allowed host characters, port range, length caps, defense against `-`-prefixed argument injection) apply uniformly.

The app re-claims both schemes on every launch via `NSWorkspace.setDefaultApplication(...)` so most wins LaunchServices arbitration even if another app tried to register `ssh://` more recently.
