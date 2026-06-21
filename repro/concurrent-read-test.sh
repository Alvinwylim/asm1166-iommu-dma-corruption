#!/bin/bash
# concurrent-read-test.sh — detect silent SATA DMA read corruption (ASM1166 et al.)
#
# Reads the SAME region of a large file N times concurrently and compares md5sums.
# A controller that mis-DMAs under IOMMU returns DIFFERENT data each read.
#   BROKEN:  >1 distinct md5  (silent corruption)
#   CLEAN:   all N identical
#
# Usage:  sudo ./concurrent-read-test.sh /path/to/file_on_suspect_disk [N] [skip_MiB] [count_MiB]
# Pick a file >2 GiB on a disk behind the suspect SATA controller.
# Run with IOMMU enabled to reproduce; re-run after the fix to confirm.
set -u

FILE="${1:?usage: $0 /path/to/large/file [N=6] [skip_MiB=1000] [count_MiB=80]}"
N="${2:-6}"; SKIP="${3:-1000}"; COUNT="${4:-80}"
[ -r "$FILE" ] || { echo "cannot read $FILE"; exit 1; }

# Force reads to hit the disk, not the page cache (needs root).
if [ "$(id -u)" = "0" ]; then sync; echo 3 > /proc/sys/vm/drop_caches; else
  echo "WARN: not root — page cache not dropped; results may be falsely clean."; fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "reading $FILE  (${COUNT} MiB @ ${SKIP} MiB offset) x${N} concurrently..."
for i in $(seq 1 "$N"); do
  dd if="$FILE" bs=1M skip="$SKIP" count="$COUNT" iflag=fullblock 2>/dev/null \
    | md5sum | awk '{print $1}' > "$tmp/$i" &
done
wait

echo "--- md5 results (count  md5) ---"
sort "$tmp"/* | uniq -c
distinct="$(sort "$tmp"/* | uniq | wc -l)"
echo "--------------------------------"
if [ "$distinct" -gt 1 ]; then
  echo "*** CORRUPTION DETECTED: $distinct distinct md5s from $N identical reads ***"
  echo "    -> controller mis-DMAs. Apply amd_iommu=off / intel_iommu=off (or the AHCI 32-bit quirk)."
  exit 2
else
  echo "CLEAN: all $N reads identical."
fi
