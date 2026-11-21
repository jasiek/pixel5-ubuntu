# Ubuntu 24.04 on the Google Pixel 5

The Pixel 5 (redfin) boots straight into plain, headless Ubuntu 24.04 arm64 on a mainline Linux kernel, reachable over SSH (USB and wifi). It is meant as a dedicated device. Sibling of the Pixel 2 project; same methods.

**What works** (mainline kernel, the default):
- SSH over USB and over wifi; Bluetooth
- charging with an 80/70 % hold, fuel gauge, thermal limits, cpufreq
- modem firmware (no SIM features: calls, SMS and mobile data are untested)
- GPU (render only: Mesa freedreno GL 4.6 / Turnip Vulkan 1.3)
- haptics (two buzzes when it is up)
- display: a text console on the screen, switched off after 60 s idle (any key, e.g. Power, wakes it)
- touchscreen (multitouch, `/dev/input/event*` "s6sy761")
- stereo speakers (`aplay -D hw:G5,0 file.wav`; starts at -20 dB, keep it low: the speaker protection firmware is not loaded)
- sensors via the ADSP: accelerometer, gyroscope, magnetometer, barometer, light (`sudo pixel5-see read accel`)

**Not yet:** microphones, headphones over USB-C, cameras, deep sleep (suspend works but saves little). Details: [`PLAN.md`](PLAN.md).

## Install

You need:
- **A computer:** an Apple Silicon Mac with Docker running. An x86 Linux host works too: the kernels cross-compile natively and the other steps need arm64 emulation, which `scripts/check-prereqs.sh` checks for.
- **Tools:** `adb` + `fastboot` (`brew install android-platform-tools`).
- **A case-sensitive volume** for the clone, with about 45 GB free. The kernel source has files whose names differ only in case; step 1 makes the volume.
- **The phone:** a Pixel 5 whose bootloader can be unlocked (no carrier-locked models).

1. **Make a case-sensitive volume.** It is a new APFS volume in your existing disk's container: it shares free space, so nothing needs partitioning.
   ```sh
   diskutil info / | grep 'APFS Container'   # e.g. "APFS Container: disk3"
   diskutil apfs addVolume disk3 'Case-sensitive APFS' Pixel2Dev   # use your container
   diskutil info /Volumes/Pixel2Dev | grep Personality   # must say "Case-sensitive APFS"
   ```
   Docker must be able to see the volume:
   - **Colima:** `colima start --mount "$HOME:w" --mount /Volumes/Pixel2Dev:w`
   - **Docker Desktop:** Settings → Resources → File sharing.
2. **Clone onto it**, then check prerequisites:
   ```sh
   cd /Volumes/Pixel2Dev && git clone https://github.com/jasiek/pixel5-ubuntu && cd pixel5-ubuntu
   scripts/check-prereqs.sh
   ```
   `check-prereqs.sh` lists anything missing, with the command that fixes it. No `--recurse-submodules` needed: the build fetches the submodules it uses as shallow clones.
3. **Download Google's factory image** `redfin-up1a.231105.001.b2` (Android 14, the last release) from <https://developers.google.com/android/images#redfin>. You must accept Google's terms on that page, so the build doesn't download it for you. Put the zip in `firmware/` unchanged; its SHA-256 is checked.
4. **Build:** `scripts/build-all.sh`.
   - It asks once for wifi details.
   - It builds `build/boot-mainline-default.img`, `build/rootfs.simg` and the downstream fallback `build/boot.img`.
   - The first run takes about 1.5 h, mostly the two kernels. Later runs rebuild only what changed. `DOWNSTREAM=0` skips the 4.19 kernel.
5. **Flash:** `scripts/flash.sh`.
   - It checks the phone before each step.
   - It **erases the phone**, and asks for `yes` first.
   - It writes only the active slot's `boot` partition and `userdata`.
   - `KERNEL=downstream scripts/flash.sh` installs the 4.19 kernel instead.
6. **Log in:** `scripts/ssh.sh` (over USB). Over wifi: `PIXEL5_HOST=pixel5.local scripts/ssh.sh`. Your `~/.ssh/*.pub` keys are installed for the user `ubuntu`.

**Never start stock Android while Ubuntu is installed.** Android offers a factory reset that wipes Ubuntu.

**Back to stock Android:** `scripts/flash.sh restore`. It runs Google's `flash-all.sh` and erases the phone.

## Background

- **How it got here:** [`PLAN.md`](PLAN.md) is the checklist (open work under **▶ RESUME HERE**). [`docs/log.md`](docs/log.md) is the dated notebook, one numbered entry per phone test.
- **Why this approach:** [`docs/research.md`](docs/research.md).
  - Ubuntu 24.04 runs from the userdata partition, with our own initramfs.
  - The default kernel is linux-next with SM7250 patches from other phone ports plus ours (`kernel/mainline/`).
  - Google's 4.19 kernel (`external/kernel-redbull`) is kept as a fallback.
- **License:** MIT for this repo's own work; kernel patches and device trees are GPL-2.0-only. Details and exceptions: [`LICENSING.md`](LICENSING.md).

Proprietary firmware, backups and build outputs live in `firmware/` and `build/`. Both are gitignored and never committed.
