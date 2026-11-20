#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Guided flashing: stock Pixel 5 (redfin) -> Ubuntu 24.04.
#
#   scripts/flash.sh           # install Ubuntu (erases the phone)
#   scripts/flash.sh restore   # back to stock Android 14 (erases the phone)
#
# One step at a time; each step checks the phone's state before going on.
# Writes only the ACTIVE slot's boot partition and userdata:
#   boot_<active>  build/boot-mainline-default.img (mainline, AVB hash footer)
#   userdata       build/rootfs.simg
# vbmeta, vendor_boot, dtbo and the bootloader partitions stay stock: with an
# AVB hash footer the unlocked bootloader boots our image as is (P5.1). The
# other slot is left alone (from the factory it is often marked unbootable).
# KERNEL=downstream flashes build/boot.img (4.19, uses the stock vendor_boot)
# instead. Needs scripts/build-all.sh's outputs and firmware/
# (scripts/get-firmware.sh). Nothing is written before you type "yes" in step 3,
# except Google's own factory image if you choose that in step 2.
#
# Never start stock Android once Ubuntu is on userdata: Android offers a
# factory reset that wipes the Ubuntu rootfs. Use `restore` instead.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=redfin-up1a.231105.001.b2   # = scripts/get-firmware.sh
STEPS=5

say()  { printf '\n\033[1m== Step %s of %s: %s\033[0m\n' "$1" "$STEPS" "$2"; }
ok()   { printf '\033[32mOK:\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWARN:\033[0m %s\n' "$*"; }
die()  { printf '\033[31mSTOP:\033[0m %s\n' "$*" >&2; exit 1; }
ask()  { local a; read -r -p "$1 [y/N] " a; [ "$a" = y ] || [ "$a" = Y ]; }
pause() { read -r -p "Press Enter when done. " _; }

[ -t 0 ] || die "Run this in a terminal: it asks questions."
for c in adb fastboot unzip; do
    command -v "$c" >/dev/null || die "'$c' not found. Install it: brew install android-platform-tools"
done

# getvar prints to stderr as "name: value". Only single named variables are
# read: `getvar all` and `fastboot devices` would print the serial number.
getvar() { fastboot getvar "$1" 2>&1 | awk -F': ' -v k="$1" '$1==k {print $2; exit}'; }

# Wait until exactly one phone is in fastboot mode.
wait_fastboot() {
    local n
    while :; do
        n=$(fastboot devices | grep -c . || true)
        [ "$n" = 1 ] && return
        [ "$n" -gt 1 ] && die "More than one phone in fastboot mode. Unplug the others."
        if [ "$(adb devices | grep -c 'device$' || true)" = 1 ]; then
            echo "Android is running with USB debugging on: rebooting it into the bootloader."
            adb reboot bootloader
        else
            echo "Waiting for the phone in bootloader mode..."
            echo "  Power it off, then hold Volume Down + Power until the bootloader screen appears."
            echo "  Plug it into this computer with a USB cable."
        fi
        sleep 5
    done
}

check_phone() {
    local product unlocked
    product=$(getvar product)
    [ "$product" = redfin ] || die "This is '$product', not a Pixel 5 (redfin). Nothing was changed."
    ok "Pixel 5 (redfin)"
    unlocked=$(getvar unlocked)
    if [ "$unlocked" != yes ]; then
        warn "The bootloader is locked."
        echo "  1. Boot Android, connect to the internet once, then Settings > About phone: tap Build number 7 times."
        echo "  2. Settings > System > Developer options: turn on OEM unlocking."
        echo "     (Greyed out = carrier-locked phone. Those can't be unlocked.)"
        echo "  3. Return to the bootloader (Volume Down + Power) and run this script again."
        echo "  Or, if OEM unlocking is already on: unlock now. This erases the phone."
        if ask "Run 'fastboot flashing unlock' now? Confirm on the phone with the volume keys + Power."; then
            fastboot flashing unlock || true
            echo "The phone erases itself and may reboot. Bring it back to the bootloader."
            pause; wait_fastboot
            [ "$(getvar unlocked)" = yes ] || die "Still locked. Nothing else was changed."
        else
            die "Bootloader locked. Nothing was changed."
        fi
    fi
    ok "bootloader unlocked"
}

[ -x "firmware/$BUILD/flash-all.sh" ] || scripts/get-firmware.sh

# ---------------------------------------------------------------------------
if [ "${1:-}" = restore ]; then
    STEPS=2
    say 1 "Find the phone"
    wait_fastboot; check_phone
    say 2 "Restore stock Android 14 ($BUILD)"
    echo "This flashes Google's factory image and ERASES everything on the phone, including Ubuntu."
    read -r -p 'Type "yes" to continue: ' a
    [ "$a" = yes ] || die "Not confirmed. Nothing was changed."
    (cd "firmware/$BUILD" && ./flash-all.sh)
    ok "Stock Android flashed. The phone boots Android; to lock the bootloader again: fastboot flashing lock."
    exit 0
fi

KERNEL=${KERNEL:-mainline}
case "$KERNEL" in
    mainline)   BOOT=build/boot-mainline-default.img; KDESC="mainline kernel" ;;
    downstream) BOOT=build/boot.img; KDESC="downstream 4.19 kernel" ;;
    *) die "KERNEL must be mainline or downstream, not '$KERNEL'." ;;
esac
for f in "$BOOT" build/rootfs.simg; do
    [ -f "$f" ] || die "Missing $f. Run scripts/build-all.sh first."
done
# The versions the factory image was made for (its android-info.txt).
INFO=$(unzip -p "firmware/$BUILD/image-$BUILD.zip" android-info.txt)
WANT_BOOTLOADER=$(printf '%s\n' "$INFO" | sed -n 's/^require version-bootloader=//p')
WANT_BASEBAND=$(printf '%s\n' "$INFO" | sed -n 's/^require version-baseband=//p')

say 1 "Find the phone"
wait_fastboot
check_phone

say 2 "Check the phone's firmware"
bl=$(getvar version-bootloader); bb=$(getvar version-baseband)
if [ "$bl" = "$WANT_BOOTLOADER" ] && [ "$bb" = "$WANT_BASEBAND" ]; then
    ok "final Android 14 firmware (bootloader $bl, radio $bb)"
else
    warn "Bootloader '$bl' / radio '$bb' are not the final versions ($WANT_BOOTLOADER / $WANT_BASEBAND)."
    echo "  Ubuntu was only tested on the final firmware ($BUILD): its kernel and the"
    echo "  firmware it loads from the vendor partition must match. Flashing Google's"
    echo "  factory image fixes this (it erases the phone and boots Android once; come"
    echo "  back to the bootloader afterwards)."
    if ask "Flash the factory image now?"; then
        (cd "firmware/$BUILD" && ./flash-all.sh)
        echo "Let Android start, then power off and hold Volume Down + Power for the bootloader."
        pause; wait_fastboot
    else
        warn "Going on with the current firmware."
    fi
fi

say 3 "Confirm"
slot=$(getvar current-slot)
case "$slot" in a|b) ;; *) die "Unknown active slot '$slot'." ;; esac
echo "About to write:"
echo "  boot_$slot (active slot)  $BOOT ($KDESC)"
echo "  userdata               build/rootfs.simg (Ubuntu 24.04)"
echo "Everything else (bootloader, radio, vendor, vbmeta, persist) stays as it is."
printf '\033[31mThis ERASES all data on the phone (userdata).\033[0m\n'
echo "Android stays installed but must not be started again: it would offer a"
echo "factory reset that wipes Ubuntu. Back to Android: scripts/flash.sh restore"
read -r -p 'Type "yes" to flash: ' a
[ "$a" = yes ] || die "Not confirmed. Nothing was changed."

say 4 "Flash"
fastboot flash "boot_$slot" "$BOOT"
# Reset the active slot's retry counter (an earlier failed boot may have
# marked it unbootable); Ubuntu marks it successful once up (qbootctl).
fastboot set_active "$slot"
fastboot flash userdata build/rootfs.simg
ok "written"
fastboot reboot || true

say 5 "Wait for Ubuntu"
echo "Waiting up to 10 min for SSH (USB 172.16.42.1 or wifi pixel5.local)..."
echo "The first boot grows the filesystem to the whole partition; it takes a little longer."
KEY=build/ssh/pixel5_ed25519
up=""
for _ in $(seq 120); do
    for h in 172.16.42.1 pixel5.local; do
        if nc -z -G 2 "$h" 22 >/dev/null 2>&1; then up=$h; break 2; fi
    done
    sleep 5
done
if [ -z "$up" ]; then
    warn "No SSH after 10 min."
    echo "  USB: the Mac sometimes creates no network interface; unplug and replug the cable."
    echo "  A hang resets itself (watchdog); hold Power ~15 s to force a restart. Notes: docs/log.md."
    exit 1
fi
ok "Ubuntu is up at $up"
echo "  Log in: ssh -i $KEY ubuntu@$up   (or PIXEL5_HOST=$up scripts/ssh.sh)"
ask "Did the phone buzz twice when it came up?" && ok "haptics" || warn "haptics: see PLAN.md P6.4"
echo "The screen shows a text console and switches off after 60 s idle; Power wakes it."
echo "Done."
