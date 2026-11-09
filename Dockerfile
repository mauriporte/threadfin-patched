# Threadfin 1.2.37 with the stream buffer on disk (osfs) instead of in memory (memfs).
# Runtime image is the official one; only the binary is swapped.
FROM fyb3roptik/threadfin:latest
COPY --chown=threadfin threadfin /home/threadfin/bin/threadfin
