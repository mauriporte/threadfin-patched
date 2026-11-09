Posted 09/11/2026 as a comment on Threadfin/Threadfin PR #669: https://github.com/Threadfin/Threadfin/pull/669#issuecomment-6747075818

---

Thanks for #669. We hit the same memfs panic, plus a second crash, on 1.2.37 while a tvheadend
scan walked about 1,150 channels at 2 streams at a time: 5 process restarts in an hour.

1. `avfs/vfs/memfs.(*MemFile).Write` panics with `slice bounds out of range` (memfs_file.go:655,
   from `thirdPartyBuffer`, buffer.go:1325) when clients disconnect quickly. The `recover` in #669
   keeps the process alive, but the stream still dies. Swapping the buffer filesystem to disk removes
   the cause; we've run this change since 08/11:

   ```diff
   -	"github.com/avfs/avfs/vfs/memfs"
   +	"github.com/avfs/avfs/vfs/osfs"
   ...
   -	bufferVFS = memfs.New()
   +	bufferVFS = osfs.NewWithNoIdm()
   ```

   (plus `checkVFSFolder()` in toolchain.go must check its `avfs.VolumeManager` cast, since osfs isn't one:
   `if vm, ok := vfs.(avfs.VolumeManager); ok && vfs.OSType() == avfs.OsWindows && ...`)

   It would also make the existing `storeBufferInRAM` setting meaningful (today `initBufferVFS()`
   always uses memfs): memfs when true, osfs when false.

2. `fatal error: concurrent map read and map write` in `createStreamID` (buffer.go:125, from
   `bufferingStream`, buffer.go:321). The stream map is read and written without a lock, so two
   channels starting at once can kill the process; `recover` can't catch this one. It needs the map
   access guarded: we hold `Lock` across the whole registration in `bufferingStream()` and take
   `Lock.RLock()` for the other `playlist.Streams` reads (`fix_race.py` in our repo). Since 08/11 no crash
   with two streams starting in the same second.

3. Leftover ffmpeg/VLC processes. `thirdPartyBuffer()` checks `clientConnection()` only between `reader.Read()`
   calls. If the source sends nothing or stalls, `Read` blocks indefinitely: the process outlives its clients,
   the 20 s start timeout is never evaluated, and each client retry starts one more process. A small watchdog
   goroutine that checks `BufferClients` once a second and kills `cmd.Process` when the key is gone fixes it
   (`fix_leftover.py` in our repo); A/B on 1.2.37: 3 leftovers before, 0 after.
