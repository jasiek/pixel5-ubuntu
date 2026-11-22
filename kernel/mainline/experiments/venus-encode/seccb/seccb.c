// SPDX-License-Identifier: GPL-2.0-only
/*
 * seccb: experiment. Give Venus' secure stream IDs their own (empty) SMMU
 * context banks, as the downstream msm_vidc secure context banks do: the
 * page table is shared with the secure VM (hyp assign), then the S2CRs the
 * hypervisor refused are written again.
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/iommu.h>
#include <linux/io-pgtable.h>
#include <linux/firmware/qcom/qcom_scm.h>
#include "arm-smmu.h"

static int skip_assign;
module_param(skip_assign, int, 0444);
static int cb = -1;	/* >= 0: route the streams to this (existing) context bank instead */
module_param(cb, int, 0444);

static int seccb_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct iommu_domain *dom = iommu_get_domain_for_dev(dev);
	struct iommu_fwspec *fwspec = dev_iommu_fwspec_get(dev);
	struct arm_smmu_master_cfg *cfg = dev_iommu_priv_get(dev);
	struct arm_smmu_domain *sd;
	struct arm_smmu_device *smmu;
	struct io_pgtable *pgt;
	struct qcom_scm_vmperm perm[2];
	u64 src = BIT(QCOM_SCM_VMID_HLOS);
	phys_addr_t pgd;
	u32 vmid = 0, v;
	int i, ret, idx;

	if (!dom || !fwspec || !cfg) {
		dev_err(dev, "seccb: no iommu domain\n");
		return -ENODEV;
	}
	of_property_read_u32(dev->of_node, "pixel5,vmid", &vmid);
	sd = container_of(dom, struct arm_smmu_domain, domain);
	smmu = cfg->smmu;
	pgt = io_pgtable_ops_to_pgtable(sd->pgtbl_ops);
	pgd = pgt->cfg.arm_lpae_s1_cfg.ttbr & GENMASK_ULL(47, 12);
	dev_info(dev, "seccb: cb %d vmid %#x ias %u pgd_bits? ttbr %pa\n", sd->cfg.cbndx, vmid, pgt->cfg.ias, &pgd);
	for (i = 0; i < fwspec->num_ids; i++) {
		idx = cfg->smendx[i];
		dev_info(dev, "seccb: before: sme %d smr %08x s2cr %08x\n", idx,
			 arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(idx)),
			 arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_S2CR(idx)));
	}
	if (!skip_assign && vmid && cb < 0) {
		perm[0].vmid = QCOM_SCM_VMID_HLOS;
		perm[0].perm = QCOM_SCM_PERM_RW;
		perm[1].vmid = vmid;
		perm[1].perm = QCOM_SCM_PERM_READ;
		ret = qcom_scm_assign_mem(pgd, PAGE_SIZE, &src, perm, 2);
		dev_info(dev, "seccb: assign pgd to vmid %#x: %d\n", vmid, ret);
	}
	for (i = 0; i < fwspec->num_ids; i++) {
		idx = cfg->smendx[i];
		v = FIELD_PREP(ARM_SMMU_S2CR_TYPE, S2CR_TYPE_TRANS) |
		    FIELD_PREP(ARM_SMMU_S2CR_CBNDX, cb >= 0 ? cb : sd->cfg.cbndx);
		arm_smmu_gr0_write(smmu, ARM_SMMU_GR0_S2CR(idx), v);
		dev_info(dev, "seccb: after: sme %d smr %08x s2cr wrote %08x reads %08x\n", idx,
			 arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(idx)), v,
			 arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_S2CR(idx)));
	}
	return 0;
}

static const struct of_device_id seccb_match[] = {
	{ .compatible = "pixel5,smmu-secure-cb" },
	{ }
};
MODULE_DEVICE_TABLE(of, seccb_match);

static struct platform_driver seccb_driver = {
	.probe = seccb_probe,
	.driver = { .name = "seccb", .of_match_table = seccb_match, .suppress_bind_attrs = true },
};
module_platform_driver(seccb_driver);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Experiment: secure SMMU context banks for Venus stream IDs");
