# threadfin-patched

Threadfin 1.2.37 with the stream buffer written to disk instead of RAM.
Runs as the CasaOS/ZimaOS app `threadfin`, image `threadfin-patched:1.2.37-fix5` (build with `TAG=1.2.37-fix5 sh build.sh <outdir>`).

## Why

Threadfin 1.2.37 (latest release, upstream `c459dd5`) crashed again and again on 08/11/2026
during the tvheadend scan of 1,154 channels: 5 restarts in one hour, and every crash dropped
every stream playing at that moment.

Two different bugs, both in `src/buffer.go`, both seen in Threadfin's own crash log:

1. **memfs write panic.** The buffer lives in an in-memory filesystem (`github.com/avfs/avfs/vfs/memfs`).
   `MemFile.Write` panics with `slice bounds out of range` (memfs_file.go:655, called from
   `thirdPartyBuffer`, buffer.go:1325). It happens when a client disconnects quickly, which a
   channel scan does all the time. It fired 113 times in the logs before this patch.
   The `storeBufferInRAM` setting doesn't help: `initBufferVFS()` always calls `memfs.New()`.
2. **`concurrent map read/iteration and map write`** in `bufferingStream` (buffer.go:125/237/321). Stream
   registration read and wrote `playlist.Streams` without holding `Lock`, so two channels starting at the
   same moment could kill the process, or one request overwrote the other's registration and its channel
   never started (seen: Canal Capital only started when tvheadend asked again 25 s later).

## The patch

`threadfin-fixes.patch` (made by applying the disk-buffer change, then `fix_race.py`, then `fix_leftover.py`):

- `src/buffer.go`: import `avfs/vfs/osfs` instead of `memfs`, and `initBufferVFS()` uses
  `osfs.NewWithNoIdm()` instead of `memfs.New()`. The buffer temp files go to Threadfin's temp folder
  on disk (`/tmp/threadfin`, mounted from `/DATA/AppData/threadfin/temp`), so the memfs panic can't happen.
- `src/toolchain.go`: `checkVFSFolder()` cast the buffer filesystem to `avfs.VolumeManager` without
  checking. Only memfs is one, so with osfs **every stream panicked** (`*osfs.OsFS is not
  avfs.VolumeManager: missing method VolumeAdd`). The cast is now checked (`vm, ok := ...`) and only used
  on Windows, where it was needed.

- `src/buffer.go` (race fix, `fix_race.py`): `bufferingStream()` holds `Lock` for the whole stream
  registration (released before the backup-stream recursion and before streaming starts), and the
  remaining `playlist.Streams` reads in `bufferingStream()` and `thirdPartyBuffer()` take `Lock.RLock()`.

- `src/buffer.go` (leftover fix, `fix_leftover.py`): `thirdPartyBuffer()` only noticed that the last client
  had gone after each `Read` from ffmpeg. When a source sent nothing (failed start) or stalled, `Read` blocked
  forever, so ffmpeg kept running with nobody watching (and its 20 s start timeout never fired); every retry
  added another copy. A watchdog now kills the process within about 1 s once the stream has no clients.

- `src/buffer.go` (fix4, `fix4.py`): `getActiveClientCount()` and `cleanUpStaleClients()` read and wrote
  `playlist.Clients` without `Lock` on every dashboard poll (found by bandit8623 on PR #669); the count now holds
  `Lock`. The leftover watchdog waits for 3 checks in a row (~3 s) without clients before it kills, so a quick
  reconnect keeps its process.

- `src/webserver.go` (fix5, `fix5.py`): the web UI's reply carried `Data.XEPG.Channels` / `Data.XMLTV.Mapping`
  while `buildXEPG`'s background goroutine wrote them (startup, scheduled updates, settings saves):
  `concurrent map iteration and map write` at webserver.go:648 vs xepg.go:478. While a build runs
  (`System.ScanInProgress == 1`, when the UI already shows maintenance.html) the reply sends empty maps.
  A build that starts between that check and `WriteJSON` can still race; closing that needs a lock in the build.

Also learned from the code: Threadfin gives up on a channel after `timeOut > 200` x 100 ms = **20 s**
(buffer.go, "Loop 1"), plus the `buffer.timeout` sleep before it starts.

### Lesson (08/11/2026)

The first build changed only `buffer.go`. It built and started fine, but no channel played, and it went
straight into production in the middle of a scan. Always test a new build on a separate copy first:

```sh
cp -a /DATA/AppData/threadfin/conf /DATA/AppData/threadfin-test/conf
docker run -d --name threadfin-test -p 34401:34400 -v /DATA/AppData/threadfin-test/conf:/home/threadfin/conf threadfin-patched:1.2.37-osfs
# fetch http://127.0.0.1:34401/m3u/threadfin.m3u, play one channel ~40 s (needs video+audio),
# then 5-6 connections cut after 3-4 s (the old crash trigger); docker logs must show no panic
docker rm -f threadfin-test
```

Leftover fix, A/B on test copies (`ab_test.sh <image>`): Nickelodeon requested 3 times (never starts):
fix2 left 3 ffmpeg running, fix3 left 0. `test_leftover.sh`: Al Jazeera's ffmpeg gone 5 s after closing; XITE Hits
watched 90 s without being cut off.

Verified this way on 08/11: Pluto TV John Wayne played (first byte 13 s, video+audio), 6 quick disconnects, 0 panics.
`stress.sh` (race fix): 6 pairs of channels started at the same instant plus quick disconnects: 0 crashes, every pair delivered video except cold-start Pluto, which is slow on its own.

10/11/2026, on test copies:
- `startup_race.sh <image> <threadfin_setup.py>` (web UI polled from container start): fix3 crashed in 2 of 3
  runs (`concurrent map iteration and map write`), fix5 survived 3 of 3 (~725 polls each).
- `test_fix4.sh` (UI polled during `stress.sh`, then a 1 s reconnect): fix3, fix4 and fix5 all 0 crashes
  (~2,600 polls). The `playlist.Clients` race was not triggered on demand; fix4's lock is from code review.
  On a normal disconnect the read loop ends ffmpeg itself, so the watchdog's grace only matters for stalled sources.

## Build and install

```sh
sh build.sh                     # on the Docker host: builds /DATA/AppData/threadfin-build/threadfin + the image
```

Then push the image to a registry the host can pull from, and change the app's image through the ZimaOS/CasaOS
app API or UI (not a bare `docker compose up`). ZimaOS always pulls on an image change, so a local-only tag fails
and the app rolls back:

```sh
docker tag threadfin-patched:1.2.37-fix5 <registry>/threadfin-patched:1.2.37-fix5
docker push <registry>/threadfin-patched:1.2.37-fix5   # then image: <registry>/threadfin-patched:1.2.37-fix5
```

**Roll back:** set the image back to the previous tag, which must be in the registry too.

**After a Threadfin restart:** fetch `http://<threadfin-host>:34400/m3u/threadfin.m3u` once. Until a
client fetches the playlist, Threadfin answers every stream with
`Steaming URL could not be found in any playlist (EC 1203)`.

## Settings in use (08/11/2026)

- buffer `ffmpeg`, `buffer.size.kb` 768, `buffer.timeout` 5000 ms (raised from 500 so slow channels get
  about 25 s before Threadfin gives up; the built-in wait is about 20 s plus this value), 6 tuners.
- tvheadend network "Threadfin": max 2 streams, `max_timeout` 60 s.

## Upstream

- Issues and discussions are turned off on Threadfin/Threadfin, so fixes go in as pull requests.
- Open PR #669 (31/10/2026, not merged) wraps the memfs panic in a `recover`, so it kills one stream instead
  of the whole app. It doesn't remove the cause and doesn't touch the `createStreamID` race.
- Upstream PR #669's `recover` can't catch the map race (Go's fatal error isn't recoverable).
- `upstream-suggestion.md`: posted 09/11/2026 as a comment on PR #669. bandit8623 replied 10/11 (taking the
  lock fix into #669; osfs only as an opt-in via `storeBufferInRAM`; leftovers belong with #667/#668).
- When upstream fixes both bugs, go back to the official image.
