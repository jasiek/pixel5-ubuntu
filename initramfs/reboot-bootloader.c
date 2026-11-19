// SPDX-License-Identifier: MIT
/* Reboot straight into fastboot: reboot(2) with RESTART2 + "bootloader".
 * busybox's reboot can't pass a reboot argument.
 *   reboot-bootloader [arg]              now ("bootloader" by default)
 *   reboot-bootloader --after S [arg]    after S seconds: a fallback timer
 *       that keeps running after switch_root (one static process, needs no
 *       files from the initramfs). Cancel it with `pkill reboot-bootloader`. */
#include <linux/reboot.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc > 2 && strcmp(argv[1], "--after") == 0) {
        unsigned left = (unsigned)strtoul(argv[2], NULL, 10);
        while (left)
            left = sleep(left);
        argv += 2;
        argc -= 2;
    }
    const char *arg = argc > 1 ? argv[1] : "bootloader";
    sync();
    return syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
                   LINUX_REBOOT_CMD_RESTART2, arg);
}
