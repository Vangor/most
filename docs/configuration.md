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
