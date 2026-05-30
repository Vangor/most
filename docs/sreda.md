# sreda — remote Claude sessions in `most`

`sreda` is a cmux/`most`-aware launcher that opens a **remote SSH workspace**
inside the `most` app and attaches a persistent [`shpool`](https://github.com/shell-pool/shpool)
session on the host, ready for a Claude run. Because the workspace is opened
through `most`'s `cmux ssh` path, the remote shell gets a reverse-tunneled
**relay** back to the app — so the sidebar can show live status pills (folder,
git branch, SSH connection, Claude state) and notifications for a session that
is actually running on another machine.

> The `sreda` command itself is **not** part of this repo. It ships in the
> user's dotfiles (`~/Git/dotfiles/sreda/`). This page documents the
> **`most`-side integration** that `sreda` drives: the `cmux ssh` workspace,
> the relay, and the shell-integration status reporting. For the relay/daemon
> internals see [`remote-daemon-spec.md`](./remote-daemon-spec.md).

## Quick start

```bash
sreda             # interactive picker (fzf): pick or create a session
sreda main        # attach to (or create) the session named "main"
sreda list        # list shpool sessions on the remote
sreda kill main   # kill the "main" session
sreda help        # usage
```

The first time you attach to a name, `shpool` creates the session; later
attaches reconnect to the same persistent session. `most` opens one
remote-SSH workspace tab per attach, named after the session so parallel
sessions stay distinguishable in the sidebar.

## Commands

| Command            | What it does                                                              |
| ------------------ | ------------------------------------------------------------------------ |
| `sreda`            | Interactive picker — lists remote sessions (via `fzf` if present, else a numbered prompt) plus a `+ new session` entry. |
| `sreda <name>`     | Attach to, or create, the named session. On first-create the `shpool` session is started. Names must match `[A-Za-z0-9_-]+`. |
| `sreda list`       | Run `shpool list` on the remote over plain SSH (no workspace opened).    |
| `sreda kill <name>`| Run `shpool kill <name>` on the remote over plain SSH.                    |
| `sreda help`       | Print usage. (`-h` / `--help` are aliases.)                              |

Only `attach` opens a `most` workspace. `list` and `kill` are read-only/control
operations that go over plain SSH and never spin up a workspace.

## Environment variables

All have defaults; override them in your shell environment before running `sreda`.

| Variable               | Default                          | Purpose                                                                 |
| ---------------------- | -------------------------------- | ----------------------------------------------------------------------- |
| `SREDA_HOST`           | `sreda`                          | SSH host to connect to.                                                 |
| `SREDA_USER`           | `vangor`                         | SSH user.                                                               |
| `SREDA_DEFAULT_SESSION`| `main`                           | Session name used when the picker is skipped / no name is given.        |
| `SREDA_SHPOOL`         | `$HOME/.cargo/bin/shpool`        | Path to `shpool` on the **remote** host.                                |
| `SREDA_SSH`            | `ssh`                            | SSH binary used for `list` / `kill` and the plain-ssh fallback.         |
| `SREDA_FZF`            | `fzf`                            | Picker binary; falls back to a numbered prompt when not installed.      |
| `SREDA_CMUX_BIN`       | auto-resolved (see below)        | Path to the `cmux` CLI. If executable, `attach` routes through `cmux ssh`. |
| `SREDA_CLAUDE_LAUNCH`  | `cmux omc launch claude`         | Command baked into the first-create `shpool attach -c …` (plain-ssh fallback path). |
| `SREDA_CMUX_SOCKET`    | auto (paired with a live DEV build) | Pins the CLI at a specific app socket so the workspace lands in the right app. |

### How `SREDA_CMUX_BIN` is resolved

If you don't set `SREDA_CMUX_BIN`, `sreda` picks the `cmux` binary like this:

1. Search `~/Library/Developer/Xcode/DerivedData` for a tagged
   `most DEV …/Contents/Resources/bin/cmux` build.
2. Use that DEV binary **only if its debug socket is live** —
   `/tmp/cmux-debug-<tag-slug>.sock` exists (i.e. the tagged app is actually
   running). When chosen, `SREDA_CMUX_SOCKET` is pinned to that socket so the
   workspace opens in your running DEV build.
3. Otherwise fall back to the installed app:
   `/Applications/most.app/Contents/Resources/bin/cmux`.

This avoids picking a stale DerivedData binary whose app isn't running (which
would fail with "Socket not found").

## How it works

End-to-end, `sreda <name>` does the following:

1. **Resolve the CLI / app socket** as described above (`SREDA_CMUX_BIN`,
   optionally `SREDA_CMUX_SOCKET`).
2. **Scrub inherited cmux context.** Any ambient `CMUX_WORKSPACE_ID`,
   `CMUX_SURFACE_ID`, `CMUX_TAB_ID`, `CMUX_PANEL_ID`, `CMUX_SOCKET`,
   `CMUX_SHELL_INTEGRATION_DIR`, `CMUX_BUNDLED_CLI_PATH`, and `CMUX_SOCKET_PATH`
   from the parent terminal are unset. Without this, `cmux ssh` would try to
   re-attach to an existing (usually gone) remote PTY instead of opening a
   fresh workspace.
3. **Invoke `cmux ssh`.** Roughly:

   ```bash
   env -u CMUX_WORKSPACE_ID … \
     "$SREDA_CMUX_BIN" ssh "$SREDA_USER@$SREDA_HOST" \
       --name "<name>" \
       --ssh-option "SetEnv SREDA_SESSION=<name>"
   ```

   The session name is **not** passed as a post-`--` remote command. It is
   propagated via `SetEnv SREDA_SESSION`, because `cmux ssh`'s bootstrap
   (writing `~/.cmux/socket_addr`, opening the reverse relay) only completes
   once the SSH session reaches the user's **interactive login shell**. A
   `-- <cmd>` would bypass that and the workspace would appear to exit
   immediately.
4. **`most` opens a managed remote-SSH workspace** and establishes the
   reverse-tunneled relay: it probes the host, provisions/uploads
   `cmuxd-remote` to `~/.cmux/bin/cmuxd-remote/<version>/<os>-<arch>/cmuxd-remote`,
   starts a background `ssh -N -R` reverse forward to a local authenticated
   relay server, and writes the relay address to `~/.cmux/socket_addr`. See
   [`remote-daemon-spec.md` §3.2 / §3.5](./remote-daemon-spec.md).
5. **The remote interactive login shell takes over.** The dotfiles zshrc
   fragment (`zshrc-sreda-shpool.zsh`) sees `SREDA_SESSION` set and, in an
   interactive shell, execs:

   ```bash
   exec ~/.cargo/bin/shpool attach "$SREDA_SESSION"
   ```

   This attaches (or creates) the persistent `shpool` session. A
   `SHPOOL_SESSION_NAME` guard prevents recursion on reattach. Claude / `omc`
   is then launched **inside** the session — currently a manual step in the
   shpool session (`cmux omc launch claude`). The `SREDA_CLAUDE_LAUNCH`
   default (`cmux omc launch claude`) is the value baked into the
   first-create `shpool attach -c …` form used on the plain-ssh fallback path;
   `cmux omc launch claude` starts Claude with cmux hooks wired in.

### Status flow back to the app

Inside the remote session the shell integration is configured for the relay:

- `CMUX_SOCKET_PATH=127.0.0.1:<relay_port>` — a **TCP** relay address (not a
  Unix socket). `cmux ssh` exports a session-local port so parallel sessions
  pin to their own relay instead of racing on a shared `socket_addr`
  ([§3.5](./remote-daemon-spec.md)).
- `CMUX_BUNDLED_CLI_PATH` points at the remote `cmuxd-remote`, which the shell
  integration uses as the relay CLI (`_cmux_relay_cli_path`).

The zsh integration detects the `host:port` form and routes sends through the
`cmuxd-remote` relay (`__v1` passthrough for v1 text commands, `rpc` for v2
JSON-RPC). It reports back:

- **cwd / folder** — `report_pwd`.
- **git branch** — `report_git_branch <branch> --status=… ` via
  `_cmux_report_git_branch_for_path` (and `clear_git_branch` when not in a repo).
- **tty** — `surface.report_tty` over the relay (`_cmux_report_tty_via_relay`).

Claude's hooks (wired by `cmux omc launch claude`) report session status the
same way. `most` turns all of this into the workspace's **sidebar pills**
(folder basename, git branch, an SSH-connection dot, and Claude status) and
**notifications** — for a process running on the remote host.

## Prerequisites

- **SSH access to the host.** A working `~/.ssh/config` `Host` entry for
  `SREDA_HOST` (key-based auth assumed; `sreda` does not manage credentials).
- **`shpool` on the remote** at `SREDA_SHPOOL` (default
  `$HOME/.cargo/bin/shpool`).
- **A `most` app that can provision `cmuxd-remote`.** For a local fork build,
  this means a **Release** `most.app` built via
  [`scripts/dogfood-release.sh`](../scripts/dogfood-release.sh). That script
  injects `CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD=1` (and `CMUXTERM_REPO_ROOT`)
  into the app's `LSEnvironment`, which is required for the local
  `cmuxd-remote` build fallback and for the daemon version to carry a
  `-dev-<fingerprint>` suffix that avoids reusing a stale cached daemon. See
  [`remote-daemon-spec.md` §3.7](./remote-daemon-spec.md) for why a plain
  locally built Release silently breaks the status feature. The build machine
  needs `go` and this repo's source.
  - A tagged **DEV** build started with `scripts/reload.sh --tag <tag>` also
    wires the allow-local-build flag and is auto-detected by `sreda` when its
    debug socket is live (see *How `SREDA_CMUX_BIN` is resolved*).

## Troubleshooting

**No sidebar pills, and `cmux: unknown command "hooks"` on the remote.**
This is the classic **stale remote daemon** symptom. A locally built Release
without the allow-local-build flag (or a public build with no manifest)
reuses a cached `cmuxd-remote` that predates the `hooks` / `omc` CLI commands,
because the bootstrap probe only checks the daemon **path** for the bare
marketing version. Rebuild and reinstall via `scripts/dogfood-release.sh`
(which gives the daemon a `-dev-<fingerprint>` version and forces a fresh
binary), then reconnect the workspace. Full explanation in
[`remote-daemon-spec.md` §3.7](./remote-daemon-spec.md).

**"Socket not found" on attach.**
`SREDA_CMUX_BIN` resolved to a tagged DEV binary whose app isn't running.
Start that DEV app, or pin `SREDA_CMUX_BIN` to the installed
`/Applications/most.app/Contents/Resources/bin/cmux`.

**`ssh-pty-attach: remote PTY attach failed`.**
`cmux ssh` inherited `CMUX_*` context from the parent terminal and tried to
re-attach an old PTY. `sreda` scrubs these automatically; if you invoked
`cmux ssh` by hand, unset `CMUX_WORKSPACE_ID` / `CMUX_SURFACE_ID` etc. first.

**Workspace exits immediately (status 1, no pane output).**
Caused by passing a post-`--` remote command to `cmux ssh`, which bypasses the
bootstrap. `sreda` deliberately uses `SetEnv SREDA_SESSION` instead; don't add
a trailing `-- <cmd>`.

**Picker prints "no TTY — pass a session name explicitly".**
The interactive picker needs a terminal. In a non-interactive context, pass an
explicit session name: `sreda <name>`.

## See also

- [`remote-daemon-spec.md`](./remote-daemon-spec.md) — the remote-SSH relay,
  `cmuxd-remote` bootstrap, CLI relay (§3.5), and local-build dogfood traps (§3.7).
- `scripts/dogfood-release.sh` — builds and installs the local Release `most.app`
  that can provision `cmuxd-remote`.
