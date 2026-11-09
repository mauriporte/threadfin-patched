#!/bin/sh
# Leftover test on the Threadfin test copy (port 34401). Counts ffmpeg processes inside the test container only.
B=http://127.0.0.1:34401
P=${PLAYLIST:-/DATA/AppData/threadfin/conf/playlist.m3u}   # the M3U Threadfin reads
tf() { docker top threadfin-test -eo pid,args 2>/dev/null | grep -c "user_agent Threadfin.*$1"; }
for i in $(seq 1 60); do curl -s -o /tmp/st.m3u $B/m3u/threadfin.m3u && [ -s /tmp/st.m3u ] && break; sleep 3; done
id() { grep -A1 ",$1\$" /tmp/st.m3u | tail -1 | sed 's#.*/stream/##'; }
for i in $(seq 1 40); do c=$(curl -s -m 2 -o /dev/null -w "%{http_code}" $B/stream/$(id "Al Jazeera")); [ "$c" != "404" ] && break; curl -s -o /dev/null $B/m3u/threadfin.m3u; sleep 5; done
sleep 5
echo "1) channel that does not start (Nickelodeon), 3 requests like tvheadend's retries"
for r in 1 2 3; do curl -s -m 27 -o /dev/null $B/stream/$(id "Nickelodeon"); done
sleep 5; echo "   Nickelodeon ffmpeg left 5 s after the last request: $(tf anixa.tv/clips/stream/nickelodeon)"
echo "2) working channel (Al Jazeera) played 25 s then closed"
curl -s -m 25 -o /tmp/aj.ts -w "   played: first byte %{time_starttransfer}s, %{size_download} bytes\n" $B/stream/$(id "Al Jazeera")
sleep 5; echo "   Al Jazeera ffmpeg left 5 s after closing: $(tf $(grep -A3 ',Al Jazeera$' "$P" | grep ^http | head -1 | cut -c1-40))"
echo "3) continuous watching for 90 s (XITE Hits): must not be cut off"
curl -s -m 90 -o /tmp/x.ts -w "   played: first byte %{time_starttransfer}s, total %{time_total}s, %{size_download} bytes\n" $B/stream/$(id "XITE Hits")
echo "   last 10 s of the 90 s still had data: $(ffprobe -v error -show_entries format=duration -of csv=p=0 /tmp/x.ts 2>/dev/null) s of video recorded"
sleep 5; echo "   XITE ffmpeg left after closing: $(tf $(grep -A3 ',XITE Hits$' "$P" | grep ^http | head -1 | cut -c1-40))"
echo "panics: $(docker logs threadfin-test 2>&1 | grep -ciE 'panic|fatal error') | $(docker inspect threadfin-test --format 'state {{.State.Status}} restarts {{.RestartCount}}')"
rm -f /tmp/st.m3u /tmp/aj.ts /tmp/x.ts
