#!/usr/bin/env bash
# dogfood-release.sh — build the signed Release `most.app`, bake in the
# remote-daemon dev-build flag, and install it to /Applications/most.app.
#
# Why the flag matters (see knowledge task 31706f6d):
#   The remote claude-status feature provisions a `cmuxd-remote` relay binary to
#   the SSH host. A real CI release embeds `CMUXRemoteDaemonManifestJSON` in
#   Info.plist (prebuilt, SHA-verified binaries). A *locally* built Release has
#   no such manifest, so without `CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD=1` the
#   app cannot build/provision the daemon at all — and worse, its bare
#   `<version>` daemon path (e.g. `0.64.10`) collides with whatever stale
#   `cmuxd-remote` is already cached on the remote, so the bootstrap reuses an
#   old binary that lacks the `hooks`/`omc` commands. The result: no sidebar
#   pills and `cmux: unknown command "hooks"` when Claude runs on the remote.
#
#   With the flag set, `remoteDaemonVersion()` becomes
#   `<version>-dev-<source-fingerprint>` (a content hash of daemon/remote), so it
#   never collides with a stale cache and the app builds/uploads a fresh,
#   hooks-capable daemon on demand. This mirrors what scripts/reload.sh already
#   does for DEV builds (reload.sh:741). It requires `go` + this repo's source on
#   the build machine, which is exactly the local dogfood setup.
#
# This is the dogfood/migration build. A public most release must instead
# publish cmuxd-remote assets and inject CMUXRemoteDaemonManifestJSON via CI
# (see scripts/build_remote_daemon_release_assets.sh + .github/workflows/release.yml).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="/tmp/most-release-build"
INSTALL_PATH="/Applications/most.app"
DEV_TEAM="${MOST_DEV_TEAM:-53SJ5Z4CRB}"
LAUNCH=0
[[ "${1:-}" == "--launch" ]] && LAUNCH=1

echo "==> Building signed Release most.app (team ${DEV_TEAM})"
xcodebuild -project "$REPO_ROOT/cmux.xcodeproj" -scheme cmux -configuration Release \
  -destination 'platform=macOS' \
  DEVELOPMENT_TEAM="$DEV_TEAM" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGN_ENTITLEMENTS="" -allowProvisioningUpdates -derivedDataPath "$DERIVED" build

BUILT_APP="$DERIVED/Build/Products/Release/most.app"
[[ -d "$BUILT_APP" ]] || { echo "build produced no app at $BUILT_APP" >&2; exit 1; }

echo "==> Installing to $INSTALL_PATH"
/usr/bin/osascript -e 'tell application id "com.4etverg.most" to quit' >/dev/null 2>&1 || true
pkill -f "most.app/Contents/MacOS/most" 2>/dev/null || true
sleep 0.5
rm -rf "$INSTALL_PATH"
cp -R "$BUILT_APP" "$INSTALL_PATH"

INFO_PLIST="$INSTALL_PATH/Contents/Info.plist"
echo "==> Injecting remote-daemon dev-build LSEnvironment flags"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$INFO_PLIST" 2>/dev/null || true
set_ls_env() {
  /usr/libexec/PlistBuddy -c "Set :LSEnvironment:$1 \"$2\"" "$INFO_PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :LSEnvironment:$1 string \"$2\"" "$INFO_PLIST"
}
set_ls_env CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD 1
set_ls_env CMUXTERM_REPO_ROOT "$REPO_ROOT"

echo "==> Re-signing (plist edit invalidated the signature)"
/usr/bin/codesign --force --deep --sign - "$INSTALL_PATH" >/dev/null 2>&1
/usr/bin/codesign --verify "$INSTALL_PATH" >/dev/null 2>&1 && echo "    signature OK"

echo "==> Done: $INSTALL_PATH"
/usr/libexec/PlistBuddy -c "Print :LSEnvironment" "$INFO_PLIST"

if [[ "$LAUNCH" == "1" ]]; then
  echo "==> Launching"
  env -u GIT_PAGER -u GH_PAGER open "$INSTALL_PATH"
fi
