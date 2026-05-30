# most

> **мост** (Russian) — *bridge*: Mac ↔ remote server, you ↔ every project, you ↔ every Claude session.

`most` is a personal fork of [cmux](https://github.com/manaflow-ai/cmux), a GPU-accelerated macOS terminal built on [Ghostty](https://github.com/ghostty-org/ghostty). It adds in-app Claude session status, deep remote-workspace integration over SSH, and a handful of robustness fixes — all under the `com.4etverg.most` bundle ID so it coexists with a production cmux install.

<!-- screenshot: app icon -->
<!-- screenshot: menubar glyph + badge -->

---

## Why this fork exists

cmux is a great terminal, but the Claude-coding workflow needed two things it doesn't have out of the box:

1. **In-app Claude status** — see which workspace is running Claude, what it's doing, and get macOS notifications when it finishes, without running an external watcher daemon.
2. **Remote workspace sidebar pills** — when you open a workspace over SSH (`cmux ssh` / `sreda`), the sidebar should show the **remote project folder** and **git branch** just like a local session, not a blank row.

Both required enough fork-specific changes that they live here rather than as upstream PRs.

---

## What's new vs upstream cmux

### In-app Claude status
- Sidebar pills show the current Claude phase (thinking, working, idle, error) per workspace, fed by the `cmux hooks claude` event pipeline already present in cmux.
- macOS notification on task completion routed through the in-app notification store — no external SSH watcher daemon required.

### Remote workspace sidebar pills
- **Project folder (basename)** — the remote shell's `report_pwd` command streams the working directory back over the TCP relay (`__v1` passthrough in `cmuxd-remote`); the sidebar shows only the last path component (e.g. `lingualex`, not `~/Git/lingualex`). Controlled by `sidebarPathLastSegmentOnly = true` (default on).
- **Git branch** — `report_git_branch` likewise streams the current branch over the relay. Fixed a bug where the local git probe (which finds no repo at a remote path on macOS) was clobbering the shell-reported branch; remote workspaces now skip the local probe entirely.

<!-- screenshot: sidebar pills (folder + branch) for a remote sreda session -->
<!-- screenshot: Claude status badge in sidebar -->

### SSH URL handler
- `ssh://user@host/path` URLs open a new `cmux ssh` workspace directly, handled by `SSHStandardURLRequest`.

### Rebrand
- Bundle ID: `com.4etverg.most` (stable release), `com.4etverg.most.debug.<tag>` (dev builds).
- App name: **most**; menubar icon and dock tile updated.
- Settings file: `~/.config/most/most.json` (same format as cmux's `cmux.json`).

<!-- screenshot: macOS notification on Claude task completion -->

### Robustness fixes (this fork's contributions)

| Fix | Details |
|-----|---------|
| **Socket classification** | All bundle-ID classification sites updated from `com.cmuxterm.app` to `com.4etverg.most` so `most` resolves its own socket instead of latching onto production cmux's. |
| **Coexistence with cmux** | Stable socket scoped to `~/Library/Application Support/most/most.sock` — `most.app` and `cmux.app` run side-by-side without stealing each other's socket. |
| **Compressed remote bootstrap** | The SSH shell-bundle (zsh integration + bash integration + claude wrapper, ~122 KB raw) is gzip+base64 compressed before inlining into the PTY command, keeping it well under Linux's `MAX_ARG_STRLEN` limit (128 KB). The raw payload caused `E2BIG` (`fork/exec /bin/sh: argument list too long`) after the claude-wrapper was added. |
| **Last-segment path display** | `sidebarPathLastSegmentOnly = true` now always shows only the basename; previously `ViewThatFits` would pick the full `~/Git/project` path whenever the sidebar was wide enough. |

---

## Build & run

### Prerequisites

```bash
./scripts/setup.sh   # initialise submodules, build GhosttyKit, install pre-commit hook
```

Requires Xcode 26.x (see `.xcode-version`).

### Dev build (tagged, isolated from installed app)

```bash
./scripts/reload.sh --tag my-feature
# prints: App path: .../most DEV my-feature.app
./scripts/reload.sh --tag my-feature --launch   # also opens it
```

Each tag gets its own bundle ID (`com.4etverg.most.debug.my-feature`), socket (`/tmp/cmux-debug-my-feature.sock`), and DerivedData path — safe to run alongside the installed release and production cmux.

### Local signed Release build

There is no notarized public release yet. To install a signed local copy:

```bash
xcodebuild \
  -project cmux.xcodeproj -scheme cmux -configuration Release \
  -destination 'platform=macOS' \
  DEVELOPMENT_TEAM=<your-apple-team-id> \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGN_ENTITLEMENTS="" \
  -allowProvisioningUpdates \
  -derivedDataPath /tmp/most-release-build \
  build

cp -R /tmp/most-release-build/Build/Products/Release/most.app /Applications/most.app
```

> `CODE_SIGN_ENTITLEMENTS=""` bypasses the `keychain-access-groups` entitlement that requires a provisioning profile scoped to the original team. Fine for local use; a proper notarized build needs the full entitlements and a Developer ID cert.

First launch may require **right-click → Open** once (Gatekeeper: Apple Development cert, not notarized).

---

## Relationship to upstream / license

- Tracks [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux) (`upstream` remote). Fork-specific work stays on `main`; upstream merges via `git merge upstream/main`.
- Submodule `ghostty` tracks [manaflow-ai/ghostty](https://github.com/manaflow-ai/ghostty), itself a fork of the upstream Ghostty renderer.
- **The upstream LICENSE is preserved unchanged.** See `LICENSE` in this repository.

---

## Roadmap

Planned, not yet done:

- **Phase D** — Cherry-pick selected upstream cmux improvements (session persistence, browser panel refinements).
- **Phase E** — `sreda2` / `shpool` replacement for more robust remote session management.
- **Friday cockpit** — SSE status feed + `most://` deep-link protocol for dashboard integration.
- **In-app rename/reconnect** — rename remote workspaces and reconnect dropped SSH sessions without leaving the app.
- **Notarized public release** — Developer ID signing + notarization so first launch doesn't require right-click → Open.
