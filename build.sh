#!/bin/sh
# Build the patched Threadfin binary and image on the Docker host.
# Usage: [TAG=1.2.37-fixN] sh build.sh [outdir]   (default /DATA/AppData/threadfin-build)
set -e
OUT=${1:-/DATA/AppData/threadfin-build}
TAG=${TAG:-1.2.37-fix4}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
cp "$HERE/threadfin-fixes.patch" "$HERE/Dockerfile" "$OUT/"
docker run --rm -e GOFLAGS=-mod=mod -v "$OUT":/out golang:1.23-bullseye sh -c '
  git clone -q --depth 1 -b 1.2.37 https://github.com/Threadfin/Threadfin /src && cd /src &&
  git apply /out/threadfin-fixes.patch &&
  CGO_ENABLED=0 go build -ldflags="-s -w" -trimpath -o /out/threadfin threadfin.go'
# ZimaOS: /root is read-only, docker needs a writable config dir
export DOCKER_CONFIG="$OUT/.docker"; mkdir -p "$DOCKER_CONFIG"
docker build -q -t threadfin-patched:$TAG "$OUT"
docker run --rm --entrypoint /home/threadfin/bin/threadfin threadfin-patched:$TAG -h 2>&1 | head -1
