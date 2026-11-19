// SPDX-License-Identifier: MIT
/* Reboot straight into fastboot: reboot(2) with RESTART2 + "bootloader".
 * busybox's reboot can't pass a reboot argument. */
#include <linux/reboot.h>
#include <sys/syscall.h>
#include <unistd.h>
int main(int argc, char **argv) {
    const char *arg = argc > 1 ? argv[1] : "bootloader";
    sync();
    return syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
                   LINUX_REBOOT_CMD_RESTART2, arg);
}
