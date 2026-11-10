# Patch Threadfin 1.2.37 src/webserver.go (after fix4.py): fix5.
# The web UI's reply (setDefaultResponseData(response, true), serialised by conn.WriteJSON at webserver.go:648)
# carries Data.XEPG.Channels and Data.XMLTV.Mapping by reference. buildXEPG's background goroutine writes those maps
# (createXEPGDatabase, xepg.go:478) at startup, at every scheduled update and after saving settings, so polling the
# UI during a build kills the process: "concurrent map iteration and map write". While a build runs
# (System.ScanInProgress == 1, the same flag that already makes the UI show maintenance.html) the reply now
# carries empty maps instead, like it already does when there are no active streams.
import sys
p = sys.argv[1]; s = open(p).read()
old = """			if len(Data.Streams.Active) > 0 {

				XEPG["epgMapping"] = Data.XEPG.Channels"""
new = """			// patched (fix5): no live XEPG maps while a build writes them
			// shortcut: a build that starts between this check and WriteJSON can still race; a full fix needs a lock in the build
			systemMutex.Lock()
			building := System.ScanInProgress == 1
			systemMutex.Unlock()

			if len(Data.Streams.Active) > 0 && !building {

				XEPG["epgMapping"] = Data.XEPG.Channels"""
assert s.count(old) == 1, s.count(old)
open(p, "w").write(s.replace(old, new)); print("fix5 applied")
