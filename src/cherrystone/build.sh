#!/bin/sh
set -e
# Build the Cherrystone ISO inside a throwaway Alpine container.
# Usage: ./build.sh [x86|x86_64]      (default x86_64)
# Needs: docker (or podman aliased to docker) and internet access.
# No docker? Use ./build-wsl.sh instead.

ARCH="${1:-x86_64}"
ALPINE="${ALPINE_VERSION:-3.22}"      # change to a newer stable release if you like
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
mkdir -p "$OUT"

TTY=""
[ -t 0 ] && TTY="-it"

# --privileged: the build mounts /proc and /dev inside the image it assembles
docker run --rm $TTY --privileged \
	-e ARCH="$ARCH" -e ALPINE="$ALPINE" \
	-v "$HERE":/src:ro -v "$OUT":/out \
	alpine:"$ALPINE" sh /src/mkiso.sh
echo "Done. ISO is in $OUT"
