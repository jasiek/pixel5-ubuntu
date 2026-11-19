# P6.2: how redfin's bootloader takes a mainline DTB, and a test plan

Research date: 2026-11-19. Nothing was flashed and the phone was not touched; everything below comes from files, source code and offline analysis of `firmware/` images.

Markers: **[verified]** means I read the code, doc or image myself. **[unverified]** means inferred or single-source. Google's redfin ABL (`r3-0.6-10489834`) is closed. Claims marked **[QC ABL]** are verified in Qualcomm's reference ABL (`fairphone-mirror/abl_tianocore_edk2`, branch `int/15/fp4`, commit `bc5379b5`). Google's fork *probably* behaves the same, but that is unverified. Where the phone's own behaviour confirms a claim, I say so.

## TL;DR

- ABL picks the base DTB from the **boot image if the header is v2**, and from **vendor_boot if it is v3** [QC ABL]. It then always applies the board overlay from `dtbo` (entry 25 on this phone). A failed overlay **aborts the boot** [QC ABL; picasso saw `Error: Dtb overlay failed`].
- So the cheapest path is the Pixel 2 one: `fastboot boot` a **header-v2** image that carries the mainline DTB, with a **dtbo sink** in that DTB. That flashes nothing. The open question is whether Google's ABL honours a v2 DTB at all. **Test it first with our known-good downstream kernel** (T0b below).
- If v2 is ignored, the next step is a mainline DTB in `vendor_boot_a` (owner OK), using slot a via `--set-active=a`. Slot b stays the way back.
- The image header must say `text_offset = 0x80000`, because Pixel ABLs refuse otherwise. Mainline sets 0, so patch the header [S: U-Boot `google-pixel.config` commit].
- pstore: stock ramoops is at `0xb7e41000` (4 MiB). A hang ends in a watchdog **cold** reset, which already wiped pstore in Tests 4–8. Before any mainline boot, measure whether a *warm* reset keeps it (T0a).

## 1. How ABL selects and patches the DTB

### 1.1 Where the DTB comes from

| Boot image header | Base DTB taken from | Vendor ramdisk / vendor cmdline | Source |
|---|---|---|---|
| v2 | the boot image's own DTB section (`dtb_size`, after kernel/ramdisk/second/recovery_dtbo) | **not loaded** (`vendor_boot` is only read when the header is ≥ v3) | `BootLinux.c` `DTBImgCheckAndAppendDT`, `UpdateBootParamsSizeAndCmdLine` [QC ABL] |
| v3 (stock redfin) | `vendor_boot` DTB section | vendor ramdisk first, then boot ramdisk; vendor cmdline first | same functions [QC ABL]; matches Tests 2/11 on the phone [verified] |

- For v3, AVB only adds `vendor_boot` to the verified set (`VerifiedBoot.c`) [QC ABL]. So a v2 `fastboot boot` does not involve the flashed vendor_boot at all [unverified on redfin].
- The kernel is loaded at RAM base + `0x80000` (`KERNEL_64BIT_LOAD_OFFSET`). The load addresses in the image header are ignored. A gzip `Image` is supported [QC ABL]. LZ4 also works, since the stock kernel is LZ4 [verified, device-info].
- **text_offset**: Heidelberg's U-Boot commit `338dbbba87` says Google added a check: *"the image header must have a specific value for the text offset"*. That value is 0x80000, so U-Boot is built with `CONFIG_TEXT_BASE=0x80080000`. Mainline arm64 has written 0 there since `120dc60d0bdb` [verified commit text].
  - The kernel never reads that field. So patching bytes 8–15 of the `Image` header to `0x80000` before compressing should be harmless [unverified].
  - On walleye, text_offset 0 booted with only a "misaligned" warning (Pixel 2 log), but that is an older ABL.
- DT budget: the DTB after the overlay must fit in 2 MiB + 1 page (`ApplyOverlay`) [QC ABL]. Overlay 25 is 353 KB, so this is fine.

### 1.2 Base-DTB matching (`GetSocDtb`, `ReadDtbFindMatch`) [QC ABL]

- **The whole DTB section is scanned as concatenated FDTs.** There is no table header.
  - Stock redfin vendor_boot holds **one** FDT: `qcom,msm-id = <0x190 0x10000>, <0x1b8 0x10000>`, `qcom,board-id = <0 0>` [verified, parsed `firmware/vendor_boot.img`].
- **`qcom,msm-id`.** Each `<id rev>` pair is tried, and the best pair wins.
  - The SoC id must equal the chip's, or the DTB is rejected.
  - The revision gives an EXACT match (`==`) or a BEST match (`<` the chip). Stock uses rev 0x10000 on a v2 (0x20000) chip, so it is a best match.
  - The foundry id must be exact or 0.
- **`qcom,board-id = <variant subtype>`.**
  - Variant low byte: platform type, exact or 0.
  - Bits 16–23 / 8–15: major / minor, `<=` the board.
  - Subtype: exact or 0.
  - DDR bits: optional bonus.
- **`qcom,pmic-id`**: optional. An absent property is not a mismatch.
- **"Exact match skips dtbo"**: `DtboNeed = FALSE` only when *all* bits are set, and that includes PMIC and softsku. So in practice the dtbo is always applied.
- **Mainline DTB root:** use `qcom,msm-id = <400 0x20000>, <440 0x20000>; qcom,board-id = <0xb1e05 0>;`, the same values as overlay 25.

### 1.3 Overlay choice and application [QC ABL unless noted]

- **Table IDs are unused.** All 36 entries in `firmware/dtbo.img` have table `id = rev = 0` [verified]. `GetBoardDtb` parses each overlay's own root `qcom,msm-id` / `qcom,board-id` with the same rules as above. Entry 25 (`0xb1e05`, PVT) wins, as `androidboot.dtbo_idx=25` confirms [verified].
- **Overlay 25 shape** [verified, decompiled]:
  - 162 fragments, all `target = <&label>`, with **no `target-path`**;
  - **174 labels** in `__fixups__`. The list ranges from `spmi_bus`, `soc`, `tlmm`, `gcc` and `reserved_memory` through `aliases`, `modem_wlan_mem`, `msm_poweroff` and the camera, audio and display labels.
- **`ufdt_overlay_apply` order:**
  1. `ufdt_overlay_root_node` **replaces every root property that already exists in the base** with the overlay's value (`merge_ufdt_into` swaps the property pointer). Missing properties are not added.
     - So a mainline root ends up with `model = "Google Inc. MSM sm7250 v2 Redfin PVT"`, `compatible = "google,redfin-sm7250", "qcom,sm7250"`, and the overlay's msm-id/board-id.
     - The phone shows this: the base model "Qualcomm Technologies, Inc. Lito SoC" became the PVT string in `live.dts` [verified].
     - This is benign on redfin, because `qcom,sm7250` survives. On nairo the rewrite to `qcom,lito` broke the UBWC and pd-mapper matches.
  2. Local fixups.
  3. `__fixups__` resolved against the base's `/__symbols__`. **No `/__symbols__`, or one missing label, aborts with `Couldn't find '%s' symbol`.** Each target node needs a phandle.
  4. Fragments are merged.
- **Any failure** → `ApplyOverlay` → `EFI_NOT_FOUND` → `Error: Dtb overlay failed` → no boot.
  - picasso logged exactly this on a Xiaomi SM7250 ABL [verified, picasso doc].
  - walleye's ABL then sat in fastboot and refused even good images ("Load Error") until `fastboot reboot-bootloader` [verified, Pixel 2 log].
- **Overlay failure is fatal.** This answers PLAN open question 5 for the QC code.
- **The "dtbo sink"**: add a `/<name>-dtbo-sink` node (no compatible, or `status = "disabled"`) with one empty child per fixup label. Give each child a phandle, and write a **hand-made `/__symbols__`** that maps every label to its child.
  - Build *without* `dtc -@`, so real mainline labels (`tlmm`, `soc`, `gcc`, `spmi_bus`, `intc`, `pdc`…) are never exported, and the overlay cannot touch real nodes.
  - Everything in the overlay lands in the sink and is ignored.
  - This is how walleye ([verified] `../ubuntu-touch-pixel2/kernel/mainline/wahoo-dtbo-sink.dtsi`) and nairo ([verified] `tools/gen_dtbo_sink.py`) did it.
- **Sink consequence:** the overlay's memory carve-outs **never take effect**. That includes `ramoops*`, `debug_info`, `ramdumplog`, `kregistry`, and the `modem_wlan_mem` resize to `0x8c000000+0x11800000`. The mainline DTS must reserve **every region in `firmware/live.dts` `/reserved-memory`** itself. walleye needed exactly this.

### 1.4 dtbo missing, erased or invalid [QC ABL]

- `LoadAndValidateDtboImg` returns FALSE on a bad magic, a bad size or a read error.
- ABL then uses `DeviceTreeAppended()` on the same DTB section, with **no overlay**. This is the legacy `platform_dt_absolute_match`, which is stricter:
  - msm-id, platform type (variant low byte), subtype, **DDR bits (subtype bits 10:8)** and soft-SKU must be **equal**;
  - revisions and PMIC revisions must be `<=`.
- So with `dtbo_a` erased, a DTB with `board-id <0xb1e05 0>` matches only if redfin's CDT DDR bits are 0 [unverified]. This is what avicii relies on, on a v2 OnePlus ABL ("needs `dtbo_a` erased").
- AVB: `dtbo` and `vendor_boot` are **hash descriptors in the top-level vbmeta**, not chained [verified, `avbtool info_image firmware/vbmeta.img`]. A changed or erased partition is a verification error that an unlocked ABL tolerates (orange) [unverified for erased dtbo].
  - `boot` is a **chain** descriptor, which is why boot_b without a footer was refused [verified, log].
  - Give any custom vendor_boot an AVB hash footer too (`--partition_name vendor_boot --partition_size 100663296`) [cheap insurance].

### 1.5 What ABL writes before the jump [QC ABL; phone observations]

- **`/memory` must exist.** `fdt_path_offset("/memory")` also matches `memory@...`. ABL **rewrites its `reg`** with the real RAM partitions and adds `ddr_device_type` and related properties.
- **`/chosen` must exist.** ABL sets `bootargs`, `linux,initrd-start/-end`, `kaslr-seed` and possibly `rng-seed`.
- **Google's ABL also adds `/chosen/cdt`** (IMEI, MACs, serials: never log it). The node is in neither the base DTB nor overlay 25, but it is in `live.dts` [verified by elimination].
- **Cmdline** = boot.img cmdline (+ vendor cmdline for v3) + the ABL `androidboot.*` list in `docs/device-info.md` (serialno, slot, dtbo_idx/dtb_idx, verifiedbootstate, …). A mainline initramfs must not print `/proc/cmdline` whole.
- Reboot reason: ABL reads `ResetReason` through a UEFI protocol (`FASTBOOT_MODE = 0x2`). Mainline `reboot-mode` on the PM8150 PON with `mode-bootloader = <0x2>` is the standard way to hit it; walleye Test 4 worked this way [QC ABL value; redfin register unverified].

## 2. What the other ports did, and what transfers from the Pixel 2

| Port | Header | DTB handling | Lesson for redfin |
|---|---|---|---|
| walleye (our Pixel 2, `../ubuntu-touch-pixel2`) | v0/1, Image.gz-dtb | `wahoo-dtbo-sink.dtsi`: 137 labels → `/wahoo-dtbo-sink`, hand-written `__symbols__`, `sink-refs` so dtc gives each dummy a phandle; factory msm-id; stock dtbo untouched; **nothing flashed** (log P8.3, Tests 1–5) [verified] | **The whole recipe transfers.** Also: **no `earlycon`** (it caused the resets); `rdinit=/bin/reboot-bootloader` as the first alive probe; `probe-init` writes dmesg to userdata, then reboots (already copied here: `initramfs/probe-init`); reserve all stock-only regions; ramoops at the stock address and layout; bootloader wiped RAM logs on walleye; mainline resets were all cold |
| nairo (Moto) | v2 | sink generated from **all** dtbo entries, explicit phandles `0x7f000000+i`, sink `status = "disabled"`; ABL "rejects modified dtbo images" [verified] | Generate, don't hand-write. The repo is AGPL-3.0, so write our own ~40-line script rather than copying |
| avicii (OnePlus) | v2 | `fastboot erase dtbo_a`; DTB `board-id <8 0>`, msm-id rev 0x10000; ramoops read over EDL crash-dump mode [verified] | Erasing dtbo is option (c). EDL memory dump is not available on a production Pixel |
| picasso (Xiaomi) | v2 | mainline DTB in the boot image → `Dtb overlay failed`; fixed with a **copydown shim**: stock DTB stays in the image for ABL, the shim swaps in an embedded mainline DTB and keeps outer `text_offset = 0x80000` [verified, doc] | Option (e) below: zero flashing, works even if only v3 is honoured, but means writing a shim |

All three SM7250 ports are header v2 (the phones launched with Android 10). **Nobody has booted mainline through a v3 / vendor_boot ABL**, and nobody has fed a v2 image to a v3 Pixel ABL. This is the core unknown.

## 3. Slots and safety

- Measured: `current-slot:b`. Slot a: `unbootable:yes`, `successful:yes`, `retry-count:0`. `max-download-size:0x10000000` [verified, `firmware/getvar-all.txt`].
- `fastboot --set-active=a` → `SetActiveSlot`: retry count = 7, **clears unbootable**, clears successful, marks a active [QC ABL].
  - A normal boot of a non-successful slot decrements the retry count. At 0 the slot is marked unbootable and ABL falls back to b.
  - So 7 failed normal boots of slot a (each ≈100 s if the watchdog bites) return the phone to slot b by itself [QC ABL; unverified on redfin].
  - `fastboot boot` does not go through `FindBootableSlot` [unverified].
- `fastboot boot` uses the **current** slot's vendor_boot/dtbo. vendor_boot_a is only reachable after `--set-active=a`.
- **Hazard:** the contents of `boot_a` are unknown, so assume the factory's Android.
  - With slot a active, any reset boots `boot_a`. If `vendor_boot_a`/`dtbo_a` are still stock-compatible, that is **Android against Ubuntu userdata** (factory-reset prompt; the CLAUDE.md never-rule).
  - **Rule:** before `--set-active=a`, flash `boot_a` with a non-Android image (owner OK): `build/boot.img` (our 4.19 + AVB footer) or the test image.
  - Way back from anywhere: Vol-Down + Power → fastboot → `fastboot --set-active=b` → `fastboot reboot`.
- **PLAN.md P6.2 says `vendor_boot_b` / `dtbo_b`.** That is now the live Ubuntu slot. It should read `_a`.

## 4. Options, in order of risk

**(a) `fastboot boot` a header-v2 image with its own DTB (nothing written).**

1. Build with `mkbootimg --header_version 2 --pagesize 4096 --base 0 --kernel_offset 0x8000 --ramdisk_offset 0x01000000 --tags_offset 0x100 --dtb_offset 0x01f00000 --os_version 14.0.0 --os_patch_level 2023-11 --kernel Image.gz --ramdisk <LZ4-legacy cpio> --dtb <dtb> --cmdline "..."`.
2. Add the AVB footer: `avbtool add_hash_footer --partition_name boot --partition_size 100663296`. The `make-bootimg.sh` `AVB_FOOTER=1` path needs a v2 variant.
3. `fastboot boot img`.

- The DTB needs the sink, because the stock `dtbo_b` still applies.
- No vendor ramdisk or vendor cmdline is used, so the cmdline must carry everything (v2: 1536 bytes).
- **Way back:** a failure resets into slot b, which is Ubuntu. If ABL wedges as on walleye, run `fastboot reboot-bootloader`.

**(e) Copydown shim, picasso style (nothing written).**

- A v3 `fastboot boot` image whose "kernel" is a small shim with `text_offset = 0x80000`. The stock vendor_boot DTB and dtbo apply as usual.
- The shim then copies `bootargs`, `linux,initrd-*`, `/memory` and `kaslr-seed` from ABL's DTB into an embedded mainline DTB, and jumps to the embedded Image at a 2 MiB-aligned address.
- It needs no sink and no flashing, and does not depend on v2 support. It is extra code (C + asm, roughly 300 lines). Use it if (a) fails and the owner prefers to avoid flashing.

**(b) Mainline DTB in `vendor_boot_a` + sink (writes `vendor_boot_a`, `boot_a`; owner OK each).**

1. `unpack_bootimg` the stock `firmware/vendor_boot.img`.
2. Repack it with `mkbootimg --header_version 3 --vendor_boot vb.img --vendor_ramdisk <stock vendor ramdisk> --vendor_cmdline "<stock>" --dtb mainline.dtb --pagesize 4096 --base 0 --kernel_offset 0x8000 --ramdisk_offset 0x01000000 --tags_offset 0x100 --dtb_offset 0x01f00000`.
   - Keep the stock vendor ramdisk, so the only change is the DTB. The concatenation is proven by Test 11.
3. Add the AVB footer.
4. `fastboot flash boot_a <safe image>`
5. `fastboot flash vendor_boot_a vb.img`
6. `fastboot --set-active=a`
7. `fastboot boot <v3 mainline img>`

- **Way back:** `fastboot --set-active=b`. Restore with `fastboot flash vendor_boot_a firmware/vendor_boot.img`.

**(c) Erase / neutralise `dtbo_a` (writes `dtbo_a`; owner OK).**

- Run `fastboot erase dtbo_a` with (b)'s `vendor_boot_a`, which drops the need for a sink.
- The DTB must pass the strict legacy match (§1.4, DDR bits unknown).
- Variant: flash a 1-entry dtbo containing an empty overlay that keeps the 0xb1e05 IDs. That still goes through the overlay path, with nothing to fix up [unverified].
- **Way back:** `fastboot flash dtbo_a firmware/dtbo.img`.

**(d) Chainload upstream U-Boot.**

- Upstream has `board/qualcomm/google-pixel.config` (lists redfin; `TEXT_BASE 0x80080000`), `qcom-phone.config`, and `doc/board/qualcomm/phones.rst`. The cover letter says Petr Vorel tested it on a Pixel 5 [S].
- But `drivers/clk/qcom/` has **no sm7250 driver** (sm8250 and sm7150 are the nearest) [verified, GitHub listing]. U-Boot also needs the same upstream redfin DTB, and its fastboot has **no UFS backend**.
- So it removes ABL from the loop only after P6.3 exists, and adds a second SoC port. Park it unless (a), (e) and (b) all fail.

## 5. Debugging without UART

**pstore on redfin.** The stock values come from the overlay (`lito-redbull-memory.dtsi`, `lito-redbull-common.dtsi`) and match `live.dts` [verified].

- `ramoops_region` `0xb7e41000` size `0x400000`: `record-size 0x20000`, `console-size 0x100000`, `pmsg-size 0x80000`, no ftrace, no ECC. That gives 20 dmesg records.
- `alt_ramoops_region` `0xb8241000` 4 MiB: Google's AES-GCM "alt" copy, read through `use_alt` and `aes_key` sysfs plus `access_ramoops` misc devices (`label` "ramoops" → alt region, "metadata" → `0xb8641000`, 4 KiB).
- `debug_info` `0xb7e01000` (256 KiB), `ramdumplog` `0xb8642000` (64 KiB). The dtsi header comment's `0xB09C1000` is stale.
- **Mainline DTS:** `ramoops@b7e41000` under `/reserved-memory`, with the **same reg, record, console and pmsg sizes and ecc 0**. Then the downstream 4.19 ramoops (same zone order: dmesg, console, ftrace, pmsg) parses mainline's records after the next boot. Mark the other three regions `no-map`.
- **Read-back:** after a failed mainline boot, the phone resets into slot b (Ubuntu, downstream) → `/sys/fs/pstore/`.
  - Ubuntu's `systemd-pstore.service` **moves** the entries to `/var/lib/systemd/pstore/` at boot, so look there [unverified for this image].
- **Reset type decides everything.**
  - A watchdog bite and our early-init reset were **cold** ("Hard Reset … cold"), and pstore was empty (Tests 4–8).
  - The bootloader leaves the APSS watchdog (`0x17c10000`) running, and it bites ≈100 s after the jump unless a kernel pets it [verified, log].
  - Mainline should enable `qcom,apss-wdt-sm8250`-style qcom-wdt (it detects the running watchdog and keeps petting), boot with `panic=10`, and possibly use `reboot=w`.
  - Whether PSCI on redfin offers SYSTEM_RESET2 (warm) is unknown: the DT says `arm,psci-1.0` [verified], and walleye's resets were all cold.

**Alive signals, earliest first:**

1. **Return to fastboot.** Use `rdinit=/bin/reboot-bootloader` (static, exists in `initramfs/`). It needs only CPUs, GIC, timer, SPMI + PM8150 PON `reboot-mode`. Seconds-to-fastboot separates "reached userspace" from a panic (`panic=10` → Ubuntu after ~40 s) and from a hang (watchdog ≈100 s → Ubuntu).
2. **`probe-init`.** It writes dmesg to `/mainline-probe/` on userdata, then returns to fastboot. It needs UFS (nairo patches) and is read from Ubuntu afterwards. Its logs contain the cmdline, so treat them as secret.
3. **pstore pmsg/console** (if T0a shows a warm reset keeps it).
4. **USB gadget** (ACM + NCM) from our initramfs: dwc3 `a600000`, SNPS 7 nm HS PHY, USB2 only (`maximum-speed = "high-speed"`, nairo/avicii `select-utmi-as-pipe-clk`). This is the P6.2 gate.
5. **Optional visual marker:** the PM8150L **flash LED** (`qcom,leds@d300`, SID 5, `status = "okay"` in live DT) via mainline `qcom,spmi-flash-led`. It needs only SPMI and is visible on the webcam. Use a short low-current torch pulse.
   - Haptics (DRV2624) has no mainline driver.
   - The panel is DSC **command mode**, so a simplefb on `cont_splash` probably shows nothing without MDP autorefresh [unverified]. Avoid static images (burn-in).

## 6. Ordered test list (one change per test)

| # | What | Writes | Gate / what it tells | Owner OK |
|---|---|---|---|---|
| T0a | Downstream Ubuntu, nothing new: (1) `echo p6-marker > /dev/pmsg0; systemctl reboot` → look for `pmsg-ramoops-0`; (2) `echo c > /proc/sysrq-trigger` → look for `console-ramoops-0`/`dmesg-ramoops-*` (check `/var/lib/systemd/pstore` too) | none | Does the bootloader keep the ramoops region over a warm reboot and a panic reboot? If not, pstore is out and probe-init/USB are the only logs | no (a panic reboot of our own kernel; mention it) |
| T0b | **v2 probe with the known-good kernel:** our 4.19 `Image.lz4` + `initramfs-ours.cpio.lz4` (KMODS=1, self-contained) + DTB = stock base DTB (`vendor_boot` FDT) + marker property `pixel5,dtb-source = "boot-v2"` (`fdtput`), header v2, stock vendor cmdline in the boot cmdline, AVB footer; `fastboot boot` | none | Boots and `/proc/device-tree/pixel5,dtb-source` exists → **ABL honours v2 DTBs → option (a)**. Boots without the marker → v2 DTB ignored → (e)/(b). fastboot error → v2 refused | no |
| T0c | Offline: generate the sink from `firmware/dtbo.img` (all 36 entries' `__fixups__`, explicit phandles, hand `__symbols__`); `fdtoverlay` entry 25 onto the mainline DTB; diff outside the sink = 0; check size < 2 MiB | none | Sink correct before any boot | no |
| T1 | First mainline boot (needs P6.1 + minimal P6.3 DTS: CPUs/PSCI/GIC/timer, all live reserved-memory, `/memory`, `/chosen`, ramoops, SPMI + PON reboot-mode, qcom-wdt, sink, IDs from §1.2), header text_offset patched to 0x80000, `rdinit=/bin/reboot-bootloader panic=10 clk_ignore_unused pd_ignore_unused` (**no earlycon**), via (a) | none | Back in fastboot within ~15 s = mainline reached userspace | no |
| T2 | Same + `probe-init` (UFS enabled) | none (writes a dir on our own userdata rootfs) | dmesg readable from Ubuntu | no |
| T3 | Same + USB gadget debug initramfs | none | `serial-sh.py` shell = **P6.2 gate** | no |
| B0 | *Only if T0b says v2 is ignored:* `boot_a` ← `build/boot.img` (safety), `vendor_boot_a` ← stock vendor_boot with the marker base DTB, `--set-active=a`, `fastboot boot build/boot.img` | `boot_a`, `vendor_boot_a`, slot flags | Slot-a mechanics with a known-good kernel; marker visible | **yes** (each flash + set-active) |
| B1–B3 | As T1–T3 but the mainline DTB is in `vendor_boot_a` (stock vendor ramdisk), v3 image | `vendor_boot_a` per DTB change | Same gates | **yes** |
| C1 | If B1 dies on the overlay: `fastboot erase dtbo_a` | `dtbo_a` | Strict legacy match passes? | **yes** |
| E/D | Shim (e) or U-Boot (d) | none | — | no |

After any B/C test: `fastboot --set-active=b` before handing the phone back. Log each as `Test N` with the seconds-to-fastboot timing.

## 7. Top unknowns

1. Does Google's ABL take the DTB from a **header-v2** boot image on this v3 device (and accept v2 at all)? T0b answers it with zero writes.
2. Does any reset on redfin keep the **ramoops region**? Watchdog resets are cold and wiped it; it is unknown whether the bootloader clears or encrypts it into `alt_ramoops` on warm reboots. T0a answers it.
3. Is Google's fork **identical to QC** in the parts that matter? That covers: the fatal overlay failure and sink acceptance, the root-property overwrite, the `text_offset == 0x80000` check (U-Boot says yes), and, for (c), the DDR bits in the strict legacy match.

## Sources

- Qualcomm reference ABL: [fairphone-mirror/abl_tianocore_edk2](https://github.com/fairphone-mirror/abl_tianocore_edk2) `int/15/fp4` @ `bc5379b5`: `QcomModulePkg/Library/BootLib/{BootLinux.c,LocateDeviceTree.c,UpdateDeviceTree.c,PartitionTableUpdate.c}`, `Library/avb/VerifiedBoot.c`, `EmbeddedPkg/Library/LibUfdt/{ufdt_overlay.c,ufdt_convert.c}`, `Application/LinuxLoader/LinuxLoader.c`.
- Local: `firmware/{dtbo,vendor_boot,vbmeta}.img` (parsed and decompiled in the scratchpad), `firmware/live.dts` (reserved-memory, wdt, PON, flash LED, root; `/chosen/cdt` only for property *names*), `firmware/getvar-all.txt`, `external/kernel-redbull/arch/arm64/boot/dts/google/{lito-v2-redfin-pvt-overlay.dts,lito-redbull-memory.dtsi,lito-redbull-common.dtsi}`, `fs/pstore/ram.c`, `drivers/misc/access_ramoops.c`, `docs/log.md` (Tests 1–24), `docs/device-info.md`.
- Pixel 2: `../ubuntu-touch-pixel2/docs/log.md` (P8.3, Tests 1–5, Test 47), `kernel/mainline/wahoo-dtbo-sink.dtsi`, `scripts/build-mainline-bootimg.sh`, `initramfs/probe-init`.
- [effeffe/nairoArchLinuxArmTools](https://github.com/effeffe/nairoArchLinuxArmTools) @ `665f098` (`tools/gen_dtbo_sink.py`, `build-nairo.sh`; AGPL-3.0); [lazybrar/avicii-mainline](https://github.com/lazybrar/avicii-mainline) @ `7194447` (README, `scripts/pack.sh`, `tools/dtbo_patch.py`, `patches/14-dts.patch`); [sm7250-mainline/docs](https://github.com/sm7250-mainline/docs) (`copydown-shim-port.md`).
- U-Boot: [commit 338dbbba87 "configs: Add google-pixel fragment config for Pixel 3, 3 XL, 5"](https://github.com/u-boot/u-boot/commit/338dbbba87), [cover letter v4](https://lists.denx.de/pipermail/u-boot/2026-January/607176.html), `doc/board/qualcomm/{phones,board}.rst`, `drivers/clk/qcom/` listing.
