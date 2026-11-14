#!/bin/bash
# Render the curated current entry for GitHub. Usage: scripts/release-notes.sh <signed: true|false>
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/release.py markdown --signed "${1:-false}" \
  --build "${GITHUB_RUN_NUMBER:-${BRK_BUILD_NUMBER:-1}}" \
  --commit "$(git rev-parse --short HEAD)"
