#!/bin/sh
set -e
# Build the Cherrystone ISO in WSL (or any Linux) without docker.
# Uses an Alpine minirootfs as a chroot, so it needs root: it re-runs itself
# with sudo. Nothing is installed on the host; everything lives in $BUILD.
# Usage: ./build-wsl.sh [x86|x86_64]      (default x86_64)
# Needs: curl, tar, internet.   Output: ./out   (or $CHERRYSTONE_OUT)

ARCH="${1:-x86_64}"
ALPINE="${ALPINE_VERSION:-3.22}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${CHERRYSTONE_OUT:-$HERE/out}"
BUILD="${CHERRYSTONE_BUILD:-/var/tmp/cherrystone-build}"
BOX="$BUILD/box-$ALPINE"
CDN="https://dl-cdn.alpinelinux.org/alpine/v$ALPINE"

mkdir -p "$OUT"
if [ "$(id -u)" != 0 ]; then
	exec sudo env ALPINE_VERSION="$ALPINE" CHERRYSTONE_OUT="$OUT" \
		CHERRYSTONE_BUILD="$BUILD" sh "$0" "$ARCH"
fi

if [ ! -x "$BOX/sbin/apk" ]; then
	echo ">> Fetching Alpine $ALPINE minirootfs"
	mkdir -p "$BUILD"
	rel="$(curl -fsSL "$CDN/releases/x86_64/latest-releases.yaml" |
		sed -n 's/^ *file: *\(alpine-minirootfs-.*\.tar\.gz\)$/\1/p' | head -n1)"
	[ -n "$rel" ] || { echo "could not find a minirootfs for Alpine $ALPINE" >&2; exit 1; }
	curl -fL -o "$BUILD/$rel" "$CDN/releases/x86_64/$rel"
	curl -fsSL -o "$BUILD/$rel.sha256" "$CDN/releases/x86_64/$rel.sha256"
	(cd "$BUILD" && sha256sum -c "$rel.sha256")
	mkdir -p "$BOX"
	tar -xzf "$BUILD/$rel" -C "$BOX"
fi
cp /etc/resolv.conf "$BOX/etc/resolv.conf"
mkdir -p "$BOX/src" "$BOX/out"

# Private mount namespace: every mount below disappears when the build exits.
export BOX HERE OUT ARCH ALPINE
export CHERRYSTONE_QUICK="${CHERRYSTONE_QUICK:-}"   # 1 = fast test build (see mkiso.sh)
exec unshare -m sh -ec '
	mount --bind "$HERE" "$BOX/src"
	mount --bind "$OUT" "$BOX/out"
	mount -t proc proc "$BOX/proc"
	mount --bind /dev "$BOX/dev"
	exec env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
		ARCH="$ARCH" ALPINE="$ALPINE" CHERRYSTONE_QUICK="$CHERRYSTONE_QUICK" \
		chroot "$BOX" /bin/sh /src/mkiso.sh
'
