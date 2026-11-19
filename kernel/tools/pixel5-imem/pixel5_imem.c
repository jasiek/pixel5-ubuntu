// SPDX-License-Identifier: GPL-2.0-only
/*
 * Read (or mark) the Pixel 5 bring-up note in on-chip IMEM, for the
 * downstream kernel. A mainline test kernel without UART or pstore writes
 * "which device it is probing" there (kernel/mainline/patches); after the
 * watchdog reset, Ubuntu loads this module to read it.
 *
 * Only a 256-byte window (off=, default 0xe00) inside the gaps the live DT
 * leaves free in IMEM 0x146ab000 is touched, never uuid_info / pmic_info,
 * which may hold identifying data.
 *
 *   insmod pixel5_imem.ko             print the note
 *   insmod pixel5_imem.ko mark=TEXT   write a test note (survival test)
 *   insmod pixel5_imem.ko clear=1     zero the window
 * The module always fails to load (-EAGAIN) so it can be reloaded at once.
 */
#include <linux/io.h>
#include <linux/module.h>
#include <linux/string.h>

#define IMEM_BASE	0x146ab000
#define NOTE_SIZE	0x100
#define NOTE_MAGIC	0x35584950	/* "PIX5" */

static char *mark;
module_param(mark, charp, 0);
static bool clear;
module_param(clear, bool, 0);
/* window offset: only gaps the live DT leaves free */
static uint off = 0xe00;
module_param(off, uint, 0);

static bool off_ok(void)
{
	static const uint gaps[][2] = {
		{ 0x200, 0x650 }, { 0xa20, 0xc70 }, { 0xda0, 0x1000 },
	};
	int i;

	for (i = 0; i < ARRAY_SIZE(gaps); i++)
		if (off >= gaps[i][0] && off + NOTE_SIZE <= gaps[i][1])
			return true;
	return false;
}

static int __init pixel5_imem_init(void)
{
	void __iomem *w;
	char text[NOTE_SIZE - 8 + 1];
	u32 magic, seq;
	int i;

	if (!off_ok())
		return -EINVAL;
	w = ioremap(IMEM_BASE + off, NOTE_SIZE);
	if (!w)
		return -ENOMEM;
	if (clear) {
		memset_io(w, 0, NOTE_SIZE);
		pr_info("pixel5_imem: cleared\n");
	} else if (mark) {
		writel(NOTE_MAGIC, w);
		writel(0, w + 4);
		for (i = 0; i < NOTE_SIZE - 9 && mark[i]; i++)
			writeb(mark[i], w + 8 + i);
		writeb(0, w + 8 + i);
		pr_info("pixel5_imem: marked\n");
	} else {
		magic = readl(w);
		seq = readl(w + 4);
		for (i = 0; i < NOTE_SIZE - 8; i++) {
			char c = readb(w + 8 + i);

			if (!c)
				break;
			text[i] = (c >= 0x20 && c < 0x7f) ? c : '?';
		}
		text[i] = 0;
		if (magic == NOTE_MAGIC)
			pr_info("pixel5_imem: @%#x note seq %u: %s\n", off, seq, text);
		else
			pr_info("pixel5_imem: @%#x no note (magic %08x)\n", off, magic);
	}
	iounmap(w);
	return -EAGAIN;
}
module_init(pixel5_imem_init);
MODULE_LICENSE("GPL");
