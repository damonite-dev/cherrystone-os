#!/bin/sh
# Helper for testing from Windows: build the given arches.
# Usage (as root in WSL):
#   sh run-build.sh x86_64 x86      full builds (what gets released)
#   sh run-build.sh quick           fast test build: 32-bit only, light
#                                   compression, downloaded packages kept
# ISOs land in ~/cherrystone-build/out (the home folder of WSL's normal user)
SRC="$(cd "$(dirname "$0")/src/cherrystone" && pwd)"
LOGS="${CHERRYSTONE_LOGS:-$(getent passwd 1000 | cut -d: -f6)/cherrystone-build}"
if [ "$1" = quick ]; then
	shift
	export CHERRYSTONE_QUICK=1
	[ $# -gt 0 ] || set -- x86
fi
for arch in "$@"; do
	start=$(date +%s)
	if CHERRYSTONE_OUT=$LOGS/out sh "$SRC/build-wsl.sh" "$arch" > "$LOGS/build-$arch.log" 2>&1; then
		echo "BUILD_OK $arch ($(( ($(date +%s) - start) / 60 )) min${CHERRYSTONE_QUICK:+, quick})"
	else
		echo "BUILD_FAILED $arch"
	fi
	grep -nE "warning|rror:|FAILURE|^>> (System|Done)" "$LOGS/build-$arch.log" | head -20
done
