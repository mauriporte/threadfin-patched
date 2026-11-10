#!/bin/sh
# fix5 test: poll the web UI from the moment a Threadfin test copy starts, while it builds XEPG.
# Usage: sh startup_race.sh <image> <threadfin_setup.py> [runs, default 3]  -> one line per run
IMG=$1; SETUP=$2; RUNS=${3:-3}; T=/DATA/AppData/threadfin-test
for r in $(seq 1 $RUNS); do
  docker rm -f threadfin-test >/dev/null 2>&1; rm -rf $T; mkdir -p $T; cp -a /DATA/AppData/threadfin/conf $T/conf
  docker run -d --name threadfin-test -p 34401:34400 -v $T/conf:/home/threadfin/conf "$IMG" >/dev/null
  n=0; end=$(( $(date +%s) + 60 ))
  while [ "$(date +%s)" -lt "$end" ] && [ "$(docker inspect -f {{.State.Running}} threadfin-test)" = true ]; do
    THREADFIN=127.0.0.1:34401 python3 "$SETUP" status >/dev/null 2>&1 && n=$((n+1))
  done
  st=$(docker inspect -f '{{.State.Status}} exit {{.State.ExitCode}}' threadfin-test)
  why=$(docker logs threadfin-test 2>&1 | grep -m1 -E 'fatal error|panic:' || echo none)
  echo "$IMG run $r: polls answered $n | $st | $why"
done
docker rm -f threadfin-test >/dev/null; rm -rf $T
