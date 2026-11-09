# Patch Threadfin 1.2.37 src/buffer.go: hold Lock across stream registration and read playlist.Streams under RLock,
# fixing "concurrent map read/iteration and map write" crashes when two streams start at the same moment.
import re, sys
p = sys.argv[1]; s = open(p).read()
def once(old, new):
    global s
    assert s.count(old) == 1, ("not unique", old[:80]); s = s.replace(old, new)
if '"sync"' not in s.split(")", 1)[0]:
    once('\t"syscall"\n', '\t"sync"\n\t"syscall"\n')
once("""	Lock.Lock()
	if p, ok := BufferInformation.Load(playlistID); !ok {
		Lock.Unlock() // Unlock early if not found
""", """	// patched: Lock is held for the whole stream registration, so two requests at the same moment can't
	// both create the playlist or iterate playlist.Streams while another goroutine writes it.
	Lock.Lock()
	unlockRegister := sync.OnceFunc(Lock.Unlock)
	defer unlockRegister()
	if p, ok := BufferInformation.Load(playlistID); !ok {
""")
once("""		playlist = p.(Playlist)
		Lock.Unlock()
""", """		playlist = p.(Playlist)
""")
head, tail = s.split("\tw.WriteHeader(200)\n\n\tfor { //Loop 1", 1)
start = head.index("unlockRegister := sync.OnceFunc")
reg = head[start:]
n_before = reg.count("BufferInformation.Store(playlistID, playlist)")
reg = re.sub(r"(\t+)Lock\.Lock\(\)\n\t+BufferInformation\.Store\(playlistID, playlist\)\n\t+Lock\.Unlock\(\)\n",
             r"\1BufferInformation.Store(playlistID, playlist)\n", reg)
assert "Lock.Lock()" not in reg and "Lock.Unlock()" not in reg.replace("sync.OnceFunc(Lock.Unlock)", ""), "lock left in registration"
assert reg.count("BufferInformation.Store(playlistID, playlist)") == n_before == 4, n_before
reg = reg.replace("\t\t\t\t// If there are backup URLs, use them\n", "\t\t\t\tunlockRegister() // patched: the backup call below re-enters bufferingStream\n\t\t\t\t// If there are backup URLs, use them\n", 1)
assert "unlockRegister() // patched: the backup" in reg
s = head[:start] + reg + "\tunlockRegister() // patched: registration done\n\n\tw.WriteHeader(200)\n\n\tfor { //Loop 1" + tail
once("""			if stream, ok := playlist.Streams[streamID]; ok {
""", """			Lock.RLock() // patched
			stream, ok := playlist.Streams[streamID]
			Lock.RUnlock()
			if ok {
""")
once("(playlist.Streams[streamID].BackupChannel1 == nil && playlist.Streams[streamID].BackupChannel2 == nil && playlist.Streams[streamID].BackupChannel3 == nil)",
     "(stream.BackupChannel1 == nil && stream.BackupChannel2 == nil && stream.BackupChannel3 == nil)")
once("""		var stream = playlist.Streams[streamID]
		var buf bytes.Buffer""", """		Lock.RLock() // patched
		var stream = playlist.Streams[streamID]
		Lock.RUnlock()
		var buf bytes.Buffer""")
once("var tmpFolder = playlist.Streams[streamID].Folder", "var tmpFolder = stream.Folder")
once("var url = playlist.Streams[streamID].URL", "var url = stream.URL")
once("""			var stream = playlist.Streams[streamID]

			if c, ok := BufferClients.Load(playlistID + stream.MD5); ok {""", """			Lock.RLock() // patched
			var stream = playlist.Streams[streamID]
			Lock.RUnlock()

			if c, ok := BufferClients.Load(playlistID + stream.MD5); ok {""")
open(p, "w").write(s); print("race patch applied")
