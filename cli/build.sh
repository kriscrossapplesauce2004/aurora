#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT/cli"
export GOCACHE=${GOCACHE:-/tmp/aurora-go-cache}
export CGO_ENABLED=0
target=${1:-all}
build() {
    mkdir -p "$ROOT/dist/cli/$1"
    GOOS=$2 GOARCH=$3 go build -trimpath -buildvcs=false -ldflags='-s -w' \
        -o "$ROOT/dist/cli/$1/aurora" .
}
case "$target" in
    host) build host linux "$(go env GOHOSTARCH)" ;;
    android) build android-arm64 android arm64 ;;
    guest) build linux-arm64 linux arm64 ;;
    all)
        build host linux "$(go env GOHOSTARCH)"
        build android-arm64 android arm64
        build linux-arm64 linux arm64
        ;;
    *) echo 'usage: cli/build.sh host|android|guest|all' >&2; exit 2 ;;
esac
