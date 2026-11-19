// SPDX-License-Identifier: GPL-2.0-only
/*
 * Pixel 5 (redfin): SMEM item 134 for the Google modem firmware.
 *
 * Google's modem firmware reads platform information from the first
 * vendor SMEM item. On the stock 4.19 kernel the "modemsmem" driver
 * (drivers/soc/qcom/modemsmem, enabled in lito-redbull-common.dtsi)
 * allocates it at boot. On redfin it holds (docs/log.md, modem prep notes):
 *   version 0, major_id 0xb, minor_id 0x28, subtype 0x2, platform 0x5,
 *   modem_flag, efs_magic, ftm_magic and dsds_magic 0.
 * All non-zero fields come from the socinfo SMEM item, so this module
 * rebuilds the item from socinfo with the downstream layout (64 bytes).
 * The flags stay zero: normal boot mode, single SIM, no modem_flag in
 * this phone's CDT (all zero downstream).
 *
 * Load before starting the modem remoteproc. Mainline equivalent for
 * qcom_q6v5_mss (SDM845 Pixels, smaller layout): David Heidelberg,
 * "remoteproc: qcom_q6v5_mss: Publish socinfo for Pixel modems" (v3).
 */
#include <linux/err.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/soc/qcom/smem.h>
#include <linux/soc/qcom/socinfo.h>

#define SMEM_ID_VENDOR0		134

/* drivers/soc/qcom/modemsmem/modemsmem.h (downstream) */
struct modem_smem_type {
	__le32 version;
	__le32 reserved_1;
	__le32 major_id;
	__le32 minor_id;
	__le32 subtype;
	__le32 platform;
	__le32 reserved_2;
	__le32 ftm_magic;
	__le32 efs_magic;
	__le32 modem_flag;
	__le32 dsds_magic;
	__le32 reserved_3[5];
};

static int __init pixel5_modemsmem_init(void)
{
	struct modem_smem_type *info;
	struct socinfo *socinfo;
	size_t size;
	u32 plat_ver;
	int ret;

	socinfo = qcom_smem_get(QCOM_SMEM_HOST_ANY, SMEM_HW_SW_BUILD_ID, NULL);
	if (IS_ERR(socinfo)) {
		pr_err("pixel5-modemsmem: no socinfo: %ld\n", PTR_ERR(socinfo));
		return PTR_ERR(socinfo);
	}
	if (le32_to_cpu(socinfo->fmt) < SOCINFO_VERSION(0, 6)) {
		pr_err("pixel5-modemsmem: socinfo format %#x too old\n",
		       le32_to_cpu(socinfo->fmt));
		return -EOPNOTSUPP;
	}

	/* -EEXIST: already allocated in this boot (module reloaded) */
	ret = qcom_smem_alloc(QCOM_SMEM_HOST_ANY, SMEM_ID_VENDOR0, sizeof(*info));
	if (ret && ret != -EEXIST) {
		pr_err("pixel5-modemsmem: alloc of item %d failed: %d\n",
		       SMEM_ID_VENDOR0, ret);
		return ret;
	}
	info = qcom_smem_get(QCOM_SMEM_HOST_ANY, SMEM_ID_VENDOR0, &size);
	if (IS_ERR(info) || size < sizeof(*info)) {
		pr_err("pixel5-modemsmem: item %d unusable\n", SMEM_ID_VENDOR0);
		return IS_ERR(info) ? PTR_ERR(info) : -EINVAL;
	}

	plat_ver = le32_to_cpu(socinfo->plat_ver);
	memset(info, 0, sizeof(*info));
	info->major_id = cpu_to_le32((plat_ver >> 16) & 0xff);
	info->minor_id = cpu_to_le32(plat_ver & 0xff);
	info->subtype = socinfo->hw_plat_subtype;
	info->platform = socinfo->hw_plat;

	pr_info("pixel5-modemsmem: item %d: major %#x minor %#x subtype %#x platform %#x\n",
		SMEM_ID_VENDOR0, le32_to_cpu(info->major_id),
		le32_to_cpu(info->minor_id), le32_to_cpu(info->subtype),
		le32_to_cpu(info->platform));
	return 0;
}
module_init(pixel5_modemsmem_init);

/* The item stays in SMEM (it cannot be freed); unloading is harmless. */
static void __exit pixel5_modemsmem_exit(void)
{
}
module_exit(pixel5_modemsmem_exit);

MODULE_DESCRIPTION("Pixel 5: SMEM item 134 (platform info) for the modem");
MODULE_LICENSE("GPL");
