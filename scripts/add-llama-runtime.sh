#!/bin/bash
# Puts the local-model runtime into a built app: llama.cpp's llama-server and the libraries it links, from upstream's
# pinned macOS arm64 release (MIT), in <app>/Contents/Helpers/llama/. Brk runs it as a helper process for the models
# the user downloads from the Max pane (Sources/BrkLocalModels); Brk itself never downloads code.
#
#   scripts/add-llama-runtime.sh dist/Brk.app
#
# The archive is fetched once into ~/.cache/brk-llama/<tag>/ and its SHA-256 checked against the pin in
# Sources/BrkLocalModels/ModelCatalog.swift (LlamaRuntime). Nothing in it runs during the build. Without network on a
# first build the step warns and leaves the app without the runtime; the Max pane then says so and every feature uses
# its fallback. The caller signs the app afterwards; the copied files are signed here first.
set -euo pipefail
APP="$1"
TAG="b12202"
SHA256="e70cd5918fb1db75652cee66bd6ab9c933cc0c5acf632f15df672c00829ebcaf"
NAME="llama-$TAG-bin-macos-arm64.tar.gz"
URL="https://github.com/ggml-org/llama.cpp/releases/download/$TAG/$NAME"
CACHE="$HOME/.cache/brk-llama/$TAG"
LIBS="libllama-server-impl.dylib libllama-common.0.dylib libmtmd.0.dylib libllama.0.dylib libggml.0.dylib libggml-cpu.0.dylib libggml-blas.0.dylib libggml-metal.0.dylib libggml-rpc.0.dylib libggml-base.0.dylib"

grep -q "\"$SHA256\"" Sources/BrkLocalModels/ModelCatalog.swift || { echo "[llama] pin differs from ModelCatalog.swift" >&2; exit 2; }
mkdir -p "$CACHE"
if [ ! -f "$CACHE/$NAME" ]; then
  if ! curl -fsSL --retry 2 -o "$CACHE/$NAME.part" "$URL"; then
    echo "[llama] could not download $URL; $APP has no local-model runtime" >&2
    rm -f "$CACHE/$NAME.part"
    exit 0
  fi
  mv "$CACHE/$NAME.part" "$CACHE/$NAME"
fi
FOUND="$(shasum -a 256 "$CACHE/$NAME" | cut -d' ' -f1)"
[ "$FOUND" = "$SHA256" ] || { echo "[llama] $NAME has SHA-256 $FOUND, expected $SHA256" >&2; rm -f "$CACHE/$NAME"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar -xzf "$CACHE/$NAME" -C "$WORK"
SRC="$WORK/llama-$TAG"
DEST="$APP/Contents/Helpers/llama"
rm -rf "$DEST"
mkdir -p "$DEST"
cp "$SRC/llama-server" "$DEST/llama-server"
# Each library under the name it is linked by (@rpath/<name>, found through the binary's @loader_path).
for lib in $LIBS; do cp -L "$SRC/$lib" "$DEST/$lib"; done
cp "$SRC/LICENSE" "$DEST/LICENSE"
for file in "$DEST"/*.dylib "$DEST/llama-server"; do codesign --force --sign - "$file" 2>/dev/null; done
echo "[llama] $TAG runtime in $DEST ($(du -sh "$DEST" | cut -f1))"
