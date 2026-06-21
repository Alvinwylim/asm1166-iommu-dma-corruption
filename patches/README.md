# patches/

`0001-ata-ahci-limit-asm1166-32bit-dma.patch` — adds the AHCI 32-bit-DMA quirk for the ASM1166 (`1b21:1166`).

> ⚠️ **The diff hunks here use illustrative `@@` context (no exact line numbers).** Before applying or submitting, **regenerate against your target tree**: edit `drivers/ata/ahci.c`, then `git format-patch -1`. Fill the `<YOUR NAME>` / `<DATE>` / `Signed-off-by` fields (DCO).
> This file will be replaced by the upstream-accepted version once the patch lands (link to the lore.kernel.org thread will be added to the top-level README *Status* section).

Apply (after regenerating offsets):
```
cd <linux-tree> && git apply patches/0001-ata-ahci-limit-asm1166-32bit-dma.patch
make drivers/ata/ahci.o   # build check
```
Or just make the 3 edits by hand — see the top-level README "Fixes" section.
