#!/bin/sh
# Stress the Threadfin test copy: pairs of channels requested at the same instant, plus quick disconnects.
B=http://127.0.0.1:34401
for i in $(seq 1 60); do curl -s -o /tmp/st.m3u $B/m3u/threadfin.m3u && [ -s /tmp/st.m3u ] && break; sleep 3; done
id() { grep -A1 ",$1\$" /tmp/st.m3u | tail -1 | sed 's#.*/stream/##'; }
for i in $(seq 1 40); do c=$(curl -s -m 2 -o /dev/null -w "%{http_code}" $B/stream/$(id "Al Jazeera")); [ "$c" != "404" ] && break; curl -s -o /dev/null $B/m3u/threadfin.m3u; sleep 5; done
PAIRS="Pluto TV John Wayne|Al Jazeera
Zee One|Nickelodeon Toons
XITE Hits|Trace UK
Outside TV|Ace TV
Pluto TV John Wayne|Zee One
Al Jazeera|XITE Hits"
ok=0; bad=0
echo "$PAIRS" | while IFS='|' read a b; do
  ( curl -s -m 30 -o /tmp/a.ts $B/stream/$(id "$a") ) & ( curl -s -m 30 -o /tmp/b.ts $B/stream/$(id "$b") ) & wait
  echo "pair: $a=$(stat -c %s /tmp/a.ts 2>/dev/null || echo 0) bytes | $b=$(stat -c %s /tmp/b.ts 2>/dev/null || echo 0) bytes"
  ( curl -s -m 3 -o /dev/null $B/stream/$(id "$a") ) & ( curl -s -m 3 -o /dev/null $B/stream/$(id "$b") ) & wait
done
echo "fatal/panic lines: $(docker logs threadfin-test 2>&1 | grep -ciE 'fatal error|panic')"
docker inspect threadfin-test --format 'state {{.State.Status}} restarts {{.RestartCount}}'
rm -f /tmp/a.ts /tmp/b.ts /tmp/st.m3u
