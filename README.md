# ASMedia ASM1166 — silent SATA data corruption with the IOMMU enabled

> **Draft for operator review (PM100 gate).** This is the proposed content for the canonical public GitHub repo (Channel B / destination #3). Suggested repo name: **`asm1166-iommu-dma-corruption`** (controller-generic → discoverable beyond any one vendor). Everything else (kernel patch, forum/Reddit posts) links *here*.
> **Scrub note:** hardware-generic; no internal hostnames / IPs / CTIDs / credentials. Only env detail = "AOOSTAR WTR MAX / Ryzen 8845HS" + a generic "5.4 TiB Ceph pool" — fine to disclose.

**TL;DR:** The ASMedia **ASM1166** SATA controller (`1b21:1166`) advertises 64-bit DMA but, on a host with the IOMMU enabled, **silently corrupts data** in transit on every attached disk. SMART is clean, there are no link resets, and no MCE — so it's invisible until your filesystems start throwing checksum/metadata errors. **Workaround today:** disable the IOMMU (`amd_iommu=off` / `intel_iommu=off`). **Proper fix:** a one-line kernel AHCI DMA quirk (patch in [`patches/`](patches/), submitted upstream — see *Status*).

---

## Affected hardware
- Any board where SATA disks hang off an **ASMedia ASM1166** (`1b21:1166`, rev 02) **and the IOMMU is enabled.**
- Confirmed on: **AOOSTAR WTR MAX** (AMD Ryzen 7 PRO 8845HS, Zen 4) — all 6 SATA bays share one ASM1166.
- **NVMe is unaffected** (different controller/DMA path).
- Same failure *class* as JMicron **JMB585** and ASMedia **ASM1061**, both already quirked in the kernel — the ASM1166 was simply never added.

## Symptom
- **Silent, non-deterministic read corruption.** A single isolated read is often clean; **concurrent reads of the same data return different garbage each time.**
- Surfaces as **XFS metadata corruption (EUCLEAN)** and, on Ceph, **mass scrub errors / inconsistent PGs** — across *different* filesystems simultaneously → it's host-level, not filesystem-level.
- **SMART clean. No SATA link resets. No MCE.** Nothing in the obvious places points at the controller.

## Root cause
The ASM1166 sets the AHCI **`CAP.S64A`** bit (claims 64-bit DMA), so the kernel trusts it (`Using 64-bit DMA addresses`). With the IOMMU on, the controller gets handed **high IOVAs (>4 GB)** that the silicon can't actually address → it reads/writes the wrong physical memory → silent corruption. No mainline DMA quirk existed for `1b21:1166` (it maps to plain `board_ahci`).

## How to detect / reproduce
1. Confirm the controller: `lspci -nn | grep -i sata` → look for `1b21:1166`.
2. Confirm 64-bit DMA is in use: `dmesg | grep -i 'ahci.*64-bit'`.
3. **Reproduce the corruption** (IOMMU on): pick a large file on a disk behind the ASM1166 and read the same region concurrently several times — the checksums differ. Script: [`repro/concurrent-read-test.sh`](repro/concurrent-read-test.sh).
   - **Broken:** the N reads produce >1 distinct md5.
   - **Fixed/clean:** all identical (and a full `ffmpeg -xerror -i big.mkv -f null -` decode shows 0 errors).
4. Drop caches first (`echo 3 | sudo tee /proc/sys/vm/drop_caches`) so reads hit the disk, not the page cache.

## Fixes (in order of preference)
1. **Kernel quirk (proper fix).** Limit the ASM1166 to 32-bit DMA via `AHCI_HFLAG_32BIT_ONLY` in `drivers/ata/ahci.c` (keeps IOMMU isolation; only cost is minor SWIOTLB bounce-buffering on >4 GB transfers). One-line-ish patch in [`patches/`](patches/); submitted to `linux-ide` (see *Status*). 32-bit is the guaranteed-correct lower bound — a later change can widen to the controller's true width if anyone characterises it.
2. **Boot parameter (immediate workaround).** `amd_iommu=off` (Intel: `intel_iommu=off`). Reliable. Trade-offs: loses IOMMU DMA isolation (acceptable on a dedicated NAS / no VFIO passthrough) + minor SWIOTLB cost. Note on AMD: `amd_iommu=pgtbl_v2` is **not** a fix on the 8845HS (its IOMMU lacks `GIOSup`), and `iommu=pt` is insufficient.
3. **Hardware.** Replace with an LSI/Broadcom HBA in IT mode (fixes it *and* keeps the IOMMU on) — if your chassis has room.

## Proof the fix holds (at scale)
After applying `amd_iommu=off`: a Ceph HDD pool on this controller was rebuilt and **deep-scrubbed end-to-end — 5.4 TiB / ~1.43M objects re-read through the fixed DMA path with 0 scrub errors → HEALTH_OK.** Before the fix, the same hardware produced six different md5s from six concurrent reads of one file. This is at-scale confirmation, not a single-file inference.

## Status
- Kernel patch: **submitted to `linux-ide`** — `<link to lore.kernel.org thread once sent>`.
- Bug report: **bugzilla.kernel.org** Drivers/Serial ATA — `<link once filed>`.
- This repo is the canonical write-up; the patch/bug/forum posts all link here.

## References
- JMicron JMB585/JMB582 AHCI DMA quirk (same class, 32-bit) — `commit 105c42566a55` (verify exact title via `git log`).
- ASMedia ASM1061 AHCI DMA quirk (same class, 43-bit) — `commit 20730e9b2778 ("ahci: add 43-bit DMA address quirk for ASMedia ASM1061 controllers")`.
- Linux `drivers/ata/ahci.c` (the quirk plumbing) — https://github.com/torvalds/linux/blob/master/drivers/ata/ahci.c
- Sibling community RCA that inspired this format: https://github.com/artmoty-dev/n5pro-jmb585-fix

## License
**CC0 1.0 (public domain)** — use freely. See [`LICENSE`](LICENSE).

## Authorship & AI assistance
Written by the repository owner **with AI assistance (Claude, `claude-opus-4.8`)**. All findings were independently **reproduced and verified on real hardware** (see *Proof the fix holds*) — the human author is responsible for the content. Commits also carry an `Assisted-by:` trailer per the open-source AI-attribution norm.

---
*Repo layout:* `README.md` · `patches/0001-ata-ahci-limit-asm1166-32bit-dma.patch` · `repro/concurrent-read-test.sh`
