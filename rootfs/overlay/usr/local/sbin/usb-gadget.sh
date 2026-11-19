#!/bin/sh
# SPDX-License-Identifier: MIT
# USB gadget: NCM network (macOS/Linux native) + ACM serial console.
# Idempotent: the initramfs creates the same gadget; this keeps it if present.
set -e
G=/sys/kernel/config/usb_gadget/g1
mountpoint -q /sys/kernel/config || mount -t configfs configfs /sys/kernel/config
if [ -n "$(cat $G/UDC 2>/dev/null)" ]; then
    echo "usb-gadget: already bound to $(cat $G/UDC)"; exit 0
fi
mkdir -p $G
echo 0x18d1 > $G/idVendor     # Google
echo 0xd001 > $G/idProduct
mkdir -p $G/strings/0x409
echo "Google"              > $G/strings/0x409/manufacturer
echo "Pixel 5 (Ubuntu)"    > $G/strings/0x409/product
echo "pixel5-ubuntu"       > $G/strings/0x409/serialnumber
mkdir -p $G/functions/ncm.usb0 $G/functions/acm.GS0
# Fixed MACs, the same as the initramfs (macOS keeps one interface name);
# safe before bind on 4.19 (the net device exists from mkdir).
echo 02:50:35:00:00:02 > $G/functions/ncm.usb0/dev_addr
echo 02:50:35:00:00:01 > $G/functions/ncm.usb0/host_addr
mkdir -p $G/configs/c.1/strings/0x409
echo "NCM + ACM" > $G/configs/c.1/strings/0x409/configuration
[ -e $G/configs/c.1/ncm.usb0 ] || ln -s $G/functions/ncm.usb0 $G/configs/c.1/
[ -e $G/configs/c.1/acm.GS0 ]  || ln -s $G/functions/acm.GS0  $G/configs/c.1/
ls /sys/class/udc | head -n1 > $G/UDC
echo "usb-gadget: bound to $(cat $G/UDC)"
