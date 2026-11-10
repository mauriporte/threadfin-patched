# Patch Threadfin 1.2.37 src/buffer.go (after the disk buffer, fix_race.py and fix_leftover.py): fix4.
# 1. getActiveClientCount() and cleanUpStaleClients() read and write playlist.Clients with no lock, from every
#    dashboard poll (setDefaultResponseData), while killClientConnection()/clientConnection() write it under Lock:
#    Go's "concurrent map" fatal error. Found by bandit8623 on Threadfin PR #669. Lock is now held for the count;
#    cleanUpStaleClients() is only called from there, so it runs inside the same lock (RWMutex is not reentrant).
# 2. The leftover watchdog killed the process on the first second the client key was missing, so a viewer
#    reconnecting within that second lost its stream. It now waits for 3 checks in a row (~3 s) without clients.
import sys
p = sys.argv[1]; s = open(p).read()


def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:60])
    s = s.replace(old, new)


sub("""func getActiveClientCount() (count int) {
	count = 0
	cleanUpStaleClients() // Ensure stale clients are removed first
""", """func getActiveClientCount() (count int) {
	// patched (fix4): playlist.Clients is written under Lock elsewhere; cleanUpStaleClients runs inside this lock
	Lock.Lock()
	defer Lock.Unlock()
	count = 0
	cleanUpStaleClients() // Ensure stale clients are removed first
""")
sub("""				if _, ok := BufferClients.Load(key); !ok {
					if cmd.Process != nil {
						cmd.Process.Kill()
					}
					return
				}
""", """				if _, ok := BufferClients.Load(key); ok {
					missing = 0
					continue
				}
				// patched (fix4): grace period, a client reconnecting within ~3 s keeps its process
				if missing++; missing < 3 {
					continue
				}
				if cmd.Process != nil {
					cmd.Process.Kill()
				}
				return
""")
sub("""		go func(key string) {
			for {""", """		go func(key string) {
			missing := 0
			for {""")
open(p, "w").write(s); print("fix4 applied")
