# Patch Threadfin 1.2.37 src/buffer.go (after fix_race.py): stop leftover ffmpeg/VLC processes.
# thirdPartyBuffer only checks for remaining clients after each Read from the process; when the source sends
# nothing or stalls, Read blocks forever and the process outlives its clients (and the 20 s start timeout).
# A watchdog now kills the process within ~1 s once the stream has no clients left.
import sys
p = sys.argv[1]; s = open(p).read()
old = """		cmd.Start()
		defer cmd.Wait()
"""
new = """		cmd.Start()
		defer cmd.Wait()

		// patched: watchdog, kill the process as soon as the stream has no clients, even while Read blocks
		watchdogDone := make(chan struct{})
		defer close(watchdogDone)
		go func(key string) {
			for {
				select {
				case <-watchdogDone:
					return
				case <-time.After(time.Second):
				}
				if _, ok := BufferClients.Load(key); !ok {
					if cmd.Process != nil {
						cmd.Process.Kill()
					}
					return
				}
			}
		}(stream.PlaylistID + stream.MD5)
"""
assert s.count(old) == 1, s.count(old)
open(p, "w").write(s.replace(old, new)); print("leftover patch applied")
