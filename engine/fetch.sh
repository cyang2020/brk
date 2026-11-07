#!/bin/bash
# Gets depot_tools and the Chromium source at exactly the pinned tag, without git history, into $BRK_CHROMIUM_ROOT.
# Safe to run again: each step continues where the last run stopped. Needs about 60 GB (source, toolchains, test data
# left out where gclient allows). Hooks run last, so an interrupted sync never leaves half-run hooks behind.
source "$(dirname "$0")/config.sh"

if [ ! -d "$BRK_DEPOT_TOOLS/.git" ]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$BRK_DEPOT_TOOLS"
fi
# First call of any depot_tools command bootstraps its private Python and CIPD client inside the depot_tools folder.
DEPOT_TOOLS_UPDATE=1 gclient --version
git -C "$BRK_DEPOT_TOOLS" rev-parse HEAD > "$BRK_CHROMIUM_ROOT/depot_tools.commit"

remote="$(git ls-remote https://chromium.googlesource.com/chromium/src.git "refs/tags/$BRK_CHROMIUM_TAG" | cut -f1)"
if [ "$remote" != "$BRK_CHROMIUM_COMMIT" ]; then
  echo "tag $BRK_CHROMIUM_TAG is at $remote, expected $BRK_CHROMIUM_COMMIT" >&2
  exit 1
fi

mkdir -p "$BRK_GCLIENT_DIR"
cd "$BRK_GCLIENT_DIR"
cat > .gclient <<GCLIENT
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {
      # No PGO profiles, no Android or ChromeOS payloads, no benchmark or layout-test data.
      "checkout_pgo_profiles": False,
      "checkout_nacl": False,
      "checkout_clang_tidy": False,
    },
  },
]
target_os = ["mac"]
target_os_only = True
GCLIENT

if [ ! -d src/.git ]; then
  git init src
  git -C src remote add origin https://chromium.googlesource.com/chromium/src.git
fi
if [ "$(git -C src rev-parse HEAD 2>/dev/null || true)" != "$BRK_CHROMIUM_COMMIT" ] \
   && [ -z "$(git -C src branch --list "$BRK_BRANCH")" ]; then
  git -C src fetch --depth=1 --no-tags origin "refs/tags/$BRK_CHROMIUM_TAG"
  git -C src checkout --detach FETCH_HEAD
fi

gclient sync --nohooks --no-history --shallow -D --force --revision "src@$BRK_CHROMIUM_COMMIT" -j 8
gclient runhooks
echo "[fetch] done at $(git -C src rev-parse HEAD)"
