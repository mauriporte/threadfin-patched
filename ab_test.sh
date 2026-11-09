#!/bin/sh
# A/B: same leftover checks on a test copy of a given image. Usage: sh ab_test.sh <image>
docker rm -f threadfin-test >/dev/null 2>&1; rm -rf /DATA/AppData/threadfin-test; mkdir -p /DATA/AppData/threadfin-test
cp -a /DATA/AppData/threadfin/conf /DATA/AppData/threadfin-test/conf
docker run -d --name threadfin-test -p 34401:34400 -v /DATA/AppData/threadfin-test/conf:/home/threadfin/conf "$1" >/dev/null
B=http://127.0.0.1:34401
tf() { docker top threadfin-test -eo pid,args 2>/dev/null | grep -c "user_agent Threadfin.*$1"; }
for i in $(seq 1 60); do curl -s -o /tmp/st.m3u $B/m3u/threadfin.m3u && [ -s /tmp/st.m3u ] && break; sleep 3; done
id() { grep -A1 ",$1\$" /tmp/st.m3u | tail -1 | sed 's#.*/stream/##'; }
for i in $(seq 1 40); do c=$(curl -s -m 2 -o /dev/null -w "%{http_code}" $B/stream/$(id "Al Jazeera")); [ "$c" != "404" ] && break; curl -s -o /dev/null $B/m3u/threadfin.m3u; sleep 5; done
sleep 5
for r in 1 2 3; do curl -s -m 27 -o /dev/null $B/stream/$(id "Nickelodeon"); done
sleep 5; nick=$(tf anixa.tv/clips/stream/nickelodeon)
for ch in "Pluto TV John Wayne" "Pluto TV Thrillers"; do curl -s -m 40 -o /dev/null $B/stream/$(id "$ch"); done
sleep 8; pluto=$(tf jmp2.uk/plu-)
echo "$1: Nickelodeon leftovers $nick | Pluto leftovers $pluto | all Threadfin ffmpeg $(tf .) | panics $(docker logs threadfin-test 2>&1 | grep -ciE 'panic|fatal error')"
docker rm -f threadfin-test >/dev/null; rm -rf /DATA/AppData/threadfin-test /tmp/st.m3u
