#!/bin/bash

# Downloads the prebuilt WebUI static library and header for this platform.
#
# We link WebUI statically, so this fetches libwebui-2-static.a rather than the
# shared library the other bindings use. The header is taken from the same
# archive on purpose: a static link welds the two together, and a webui.h that
# disagrees with the .a produces a corrupt build rather than an honest error.
#
#   bash bootstrap.sh                             # nightly, current platform
#   WEBUI_VERSION=2.5.0-beta.3 bash bootstrap.sh  # pin a tagged release
#
# Re-running this after a nightly moves will relink the NIF on the next
# `mix compile` -- the Makefiles depend on the static library, not just on the
# C source.
#
# Windows uses bootstrap.bat.

set -euo pipefail

VERSION="${WEBUI_VERSION:-nightly}"
BASE_URL="https://github.com/webui-dev/webui/releases/download/${VERSION}"

OS="linux"
CC="gcc"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    CC="clang"
fi

ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
    x86_64 | amd64) ARCH="x64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    arm*) ARCH="arm" ;;
    *)
        echo "Error: unsupported architecture '$ARCH_RAW'" >&2
        exit 1
        ;;
esac

TARGET="webui-${OS}-${CC}-${ARCH}"
CACHE="cache"

echo "WebUI Elixir Bootstrap"
echo "* Target:  $TARGET"
echo "* Version: $VERSION"

cleanup() { rm -rf "$CACHE"; }
trap cleanup EXIT

rm -rf "$CACHE"
mkdir -p "$CACHE"

echo "* Downloading [$TARGET.zip]..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$BASE_URL/$TARGET.zip" -o "$CACHE/$TARGET.zip"
elif command -v wget >/dev/null 2>&1; then
    wget -q "$BASE_URL/$TARGET.zip" -O "$CACHE/$TARGET.zip"
else
    echo "Error: need curl or wget" >&2
    exit 1
fi

echo "* Extracting..."
unzip -q "$CACHE/$TARGET.zip" -d "$CACHE"

# The release archives are not laid out consistently -- the Linux and macOS
# workflows zip the folder itself, the Windows one zips its contents -- so
# locate the files instead of assuming a path.
STATIC_LIB=$(find "$CACHE" -name "libwebui-2-static.a" -type f | head -n 1)
HEADER=$(find "$CACHE" -name "webui.h" -type f | head -n 1)

if [ -z "$STATIC_LIB" ]; then
    echo "Error: libwebui-2-static.a not found in $TARGET.zip" >&2
    exit 1
fi

if [ -z "$HEADER" ]; then
    echo "Error: webui.h not found in $TARGET.zip" >&2
    exit 1
fi

mkdir -p "$TARGET"
cp -f "$STATIC_LIB" "$TARGET/libwebui-2-static.a"
cp -f "$HEADER" "$TARGET/webui.h"

echo "* Installed into [$TARGET/]"
echo "Done. Build with: mix compile"
