#!/bin/sh
# fix4 tests on a Threadfin test copy (port 34401). Usage: sh test_fix4.sh <image> <dir with stress.sh> <threadfin_setup.py>
# 1) dashboard polls (getActiveClientCount) hammered while pairs of channels start and stop (the client-map race)
# 2) quick reconnect: a viewer that comes back within 1 s keeps its ffmpeg (watchdog grace period)
IMG=$1; HERE=$2; SETUP=$3; T=/DATA/AppData/threadfin-test; B=http://127.0.0.1:34401
docker rm -f threadfin-test >/dev/null 2>&1; rm -rf $T; mkdir -p $T
cp -a /DATA/AppData/threadfin/conf $T/conf
docker run -d --name threadfin-test -p 34401:34400 -v $T/conf:/home/threadfin/conf "$IMG" >/dev/null
tf() { docker top threadfin-test -eo pid,args 2>/dev/null | grep -c "user_agent Threadfin.*$1"; }
for i in $(seq 1 60); do curl -s -o /tmp/st.m3u $B/m3u/threadfin.m3u && [ -s /tmp/st.m3u ] && break; sleep 3; done
id() { grep -A1 ",$1\$" /tmp/st.m3u | tail -1 | sed 's#.*/stream/##'; }

# shortcut: fixed 90 s wait for Threadfin's startup XEPG build; polling during that build hits a separate,
# unpatched race (Data.XEPG.Channels serialised in webserver.go:648 while xepg.go writes it)
sleep 90
echo "1) dashboard polls during paired starts"
( n=0; while [ ! -f /tmp/fix4.stop ]; do THREADFIN=127.0.0.1:34401 python3 "$SETUP" status >/dev/null 2>&1 && n=$((n+1)); done; echo "   dashboard polls answered: $n" ) &
sh "$HERE/stress.sh" | sed 's/^/   /'
touch /tmp/fix4.stop; wait; rm -f /tmp/fix4.stop

echo "2) quick reconnect (Al Jazeera): 10 s, cut, back after 1 s for 20 s"
curl -s -o /tmp/st.m3u $B/m3u/threadfin.m3u  # stress.sh removes its copy
curl -s -m 10 -o /dev/null $B/stream/$(id "Al Jazeera"); sleep 1
before=$(tf .)
curl -s -m 20 -o /tmp/rc.ts -w "   second viewing: first byte %{time_starttransfer}s, %{size_download} bytes\n" $B/stream/$(id "Al Jazeera")
echo "   Threadfin ffmpeg while reconnected (1 = kept, 0 = killed): $before"
sleep 6; echo "   ffmpeg left 6 s after the viewer left (expect 0): $(tf .)"

echo "panics/fatal: $(docker logs threadfin-test 2>&1 | grep -ciE 'panic|fatal error') | $(docker inspect threadfin-test --format 'state {{.State.Status}} restarts {{.RestartCount}}')"
docker logs threadfin-test > "${LOG:-/tmp/threadfin-test.log}" 2>&1  # full log kept for crash traces
docker rm -f threadfin-test >/dev/null; rm -rf $T /tmp/st.m3u /tmp/rc.ts
