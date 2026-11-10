#!/bin/bash
# Writes the GitHub release notes for a build (.github/workflows/release.yml; docs/release.md): what the build is,
# which zip to download, how to open it, and the commits since the previous build.
#
#   scripts/release-notes.sh <label> <previous build: commit, tag or empty> <signed: true|false> > notes.md
#
# The previous build is the commit the `latest` tag pointed to (rolling builds) or the previous v* tag (releases);
# when it is empty or not an ancestor of HEAD (history rewritten), the last 30 commits are listed instead.
set -euo pipefail
LABEL="${1:?usage: release-notes.sh <label> <previous> <signed>}"
PREVIOUS="${2:-}"
SIGNED="${3:-false}"
PRODUCT="${PRODUCT:-Brk}"
HEAD_SHORT="$(git rev-parse --short HEAD)"
MAX=200

echo "$PRODUCT $LABEL for macOS 14 or later, built from \`$HEAD_SHORT\`${GITHUB_RUN_NUMBER:+ (build $GITHUB_RUN_NUMBER)}."
echo
echo "- Apple silicon (M1 and later): \`$PRODUCT-$LABEL-arm64.zip\`"
echo "- Intel: \`$PRODUCT-$LABEL-x86_64.zip\`"
echo
echo "Unzip it and move $PRODUCT.app to Applications."
echo
if [ "$SIGNED" = "true" ]; then
  echo "Signed with a Developer ID and notarized by Apple, so it opens like any downloaded app."
else
  echo "### Opening it the first time"
  echo
  echo "This build is signed ad hoc, not by an identified developer, so macOS refuses to open it at first. Either:"
  echo
  echo "- run \`xattr -dr com.apple.quarantine /Applications/$PRODUCT.app\` in Terminal, then open it normally; or"
  echo "- right-click (Control-click) $PRODUCT.app, choose Open, then Open again. On macOS 15 and later that menu no"
  echo "  longer offers Open: double-click once, then go to System Settings > Privacy & Security and click Open Anyway."
fi
echo

if [ -n "$PREVIOUS" ] && git merge-base --is-ancestor "$PREVIOUS" HEAD 2>/dev/null; then
  RANGE="$PREVIOUS..HEAD"
  echo "### Changes since \`$(git rev-parse --short "$PREVIOUS^{commit}")\`"
else
  RANGE="-n 30 HEAD"
  echo "### Latest changes"
fi
echo
# shellcheck disable=SC2086
COMMITS="$(git log --no-merges --format='- %s (%h)' $RANGE)"
COUNT="$(printf '%s' "$COMMITS" | grep -c '^' || true)"
if [ "$COUNT" -eq 0 ]; then
  echo "No code commits since the previous build."
else
  printf '%s\n' "$COMMITS" | head -n "$MAX"
  [ "$COUNT" -gt "$MAX" ] && echo "- … and $((COUNT - MAX)) more"
fi
true
