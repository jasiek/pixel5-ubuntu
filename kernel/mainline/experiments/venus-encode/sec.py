# SPDX-License-Identifier: GPL-2.0-only
# SEC: the encoder's INTERNAL_PERSIST buffer goes into the secure non-pixel context bank
# (downstream msm_smem alloc_dma_mem: PERSIST of an encoder session is always CP_NON_PIXEL).
# Needs DT nodes soc@0:venus-sec-np (iommus 0x1304/0xe0) and the seccb module loaded.
p=open('helpers.c').read()
a='#include "hfi_parser.h"\n'
assert p.count(a)==1
code=r'''#include <linux/iommu.h>
#include <linux/io-pgtable.h>
#include <linux/platform_device.h>
#include <linux/firmware/qcom/qcom_scm.h>
#include "../../../../iommu/arm/arm-smmu/arm-smmu.h"

static unsigned int sec_types = BIT(HFI_BUFFER_INTERNAL_PERSIST & 0xf);	/* low nibble of the HFI type */
module_param(sec_types, uint, 0644);
static unsigned int sec_vmid = QCOM_SCM_VMID_CP_NON_PIXEL;
static phys_addr_t sec_tables[64];
static unsigned int sec_ntables;

static int sec_assign(struct device *dev, phys_addr_t phys, int perm)
{
	struct qcom_scm_vmperm vp[2] = {
		{ .vmid = QCOM_SCM_VMID_HLOS, .perm = QCOM_SCM_PERM_RW },
		{ .vmid = sec_vmid, .perm = perm },
	};
	u64 src = BIT(QCOM_SCM_VMID_HLOS);
	int ret;

	ret = qcom_scm_assign_mem(phys, PAGE_SIZE, &src, vp, 2);
	if (ret)
		dev_err(dev, "DBG SEC: assign %pa failed: %d\n", &phys, ret);
	return ret;
}

/* buffer memory: owned by the secure VM alone, like the downstream secure heap */
static int sec_give(struct device *dev, phys_addr_t phys, bool give)
{
	struct qcom_scm_vmperm vp = {
		.vmid = give ? sec_vmid : QCOM_SCM_VMID_HLOS,
		.perm = give ? QCOM_SCM_PERM_RW : QCOM_SCM_PERM_RWX,
	};
	u64 src = give ? BIT(QCOM_SCM_VMID_HLOS) : BIT(sec_vmid);
	int ret;

	ret = qcom_scm_assign_mem(phys, PAGE_SIZE, &src, &vp, 1);
	if (ret)
		dev_err(dev, "DBG SEC: %s %pa failed: %d\n", give ? "give" : "take back", &phys, ret);
	return ret;
}

static bool venus_sec_np_unmap(struct venus_core *core, dma_addr_t da, dma_addr_t fw_da, size_t size)
{
	struct device *np = bus_find_device_by_name(&platform_bus_type, NULL, "soc@0:venus-sec-np");
	struct iommu_domain *nd = np ? iommu_get_domain_for_dev(np) : NULL;
	struct iommu_domain *vd = iommu_get_domain_for_dev(core->dev);
	bool ok = true;
	size_t off;

	if (!nd || !vd)
		return false;
	size = PAGE_ALIGN(size);
	iommu_unmap(nd, fw_da, size);
	for (off = 0; off < size; off += PAGE_SIZE)
		if (sec_give(core->dev, iommu_iova_to_phys(vd, da + off), false))
			ok = false;
	return ok;
}

static void sec_assign_table(struct device *dev, phys_addr_t phys)
{
	unsigned int i;

	for (i = 0; i < sec_ntables; i++)
		if (sec_tables[i] == phys)
			return;
	if (sec_ntables < ARRAY_SIZE(sec_tables))
		sec_tables[sec_ntables++] = phys;
	sec_assign(dev, phys, QCOM_SCM_PERM_READ);
	dev_info(dev, "DBG SEC: page table %pa shared with vmid %#x\n", &phys, sec_vmid);
}

static dma_addr_t venus_sec_np_map(struct venus_core *core, dma_addr_t da, size_t size)
{
	static dma_addr_t next = 0x10000000;
	struct device *dev = core->dev;
	struct device *np = bus_find_device_by_name(&platform_bus_type, NULL, "soc@0:venus-sec-np");
	struct iommu_domain *nd, *vd = iommu_get_domain_for_dev(dev);
	struct arm_smmu_domain *sd;
	struct io_pgtable *pgt;
	dma_addr_t base, iova;
	phys_addr_t phys;
	u64 *l1, *l2, e;
	size_t off;
	int ret;

	if (!np || !vd)
		return 0;
	nd = iommu_get_domain_for_dev(np);
	if (!nd)
		return 0;
	size = PAGE_ALIGN(size);
	base = next;
	next += size + SZ_1M;
	for (off = 0; off < size; off += PAGE_SIZE) {
		phys = iommu_iova_to_phys(vd, da + off);
		if (!phys || sec_give(dev, phys, true))
			goto undo;
		ret = iommu_map(nd, base + off, phys, PAGE_SIZE, IOMMU_READ | IOMMU_WRITE, GFP_KERNEL);
		if (ret) {
			dev_err(dev, "DBG SEC: map failed: %d\n", ret);
			sec_give(dev, phys, false);
			goto undo;
		}
	}
	goto tables;
undo:
	if (off)
		iommu_unmap(nd, base, off);
	while (off) {
		off -= PAGE_SIZE;
		sec_give(dev, iommu_iova_to_phys(vd, da + off), false);
	}
	return 0;
tables:
	/* every page table page must be readable by the secure VM (downstream arm_smmu_assign_table) */
	sd = container_of(nd, struct arm_smmu_domain, domain);
	pgt = io_pgtable_ops_to_pgtable(sd->pgtbl_ops);
	l1 = phys_to_virt(pgt->cfg.arm_lpae_s1_cfg.ttbr & GENMASK_ULL(47, 12));
	for (iova = base; iova < base + size; iova += SZ_2M) {
		e = l1[(iova >> 30) & 0x3f];
		if ((e & 3) != 3)
			continue;
		sec_assign_table(dev, e & GENMASK_ULL(47, 12));
		l2 = phys_to_virt(e & GENMASK_ULL(47, 12));
		e = l2[(iova >> 21) & 0x1ff];
		if ((e & 3) == 3)
			sec_assign_table(dev, e & GENMASK_ULL(47, 12));
	}
	iova = base + size - PAGE_SIZE;
	e = l1[(iova >> 30) & 0x3f];
	if ((e & 3) == 3) {
		l2 = phys_to_virt(e & GENMASK_ULL(47, 12));
		e = l2[(iova >> 21) & 0x1ff];
		if ((e & 3) == 3)
			sec_assign_table(dev, e & GENMASK_ULL(47, 12));
	}
	return base;
}

'''
p=p.replace(a,a+code)
a='struct intbuf {\n'
assert p.count(a)==1
p=p.replace(a,a+'\tdma_addr_t fw_da;\n')
a='''		bd.device_addr = buf->da;

		ret = hfi_session_set_buffers(inst, &bd);'''
assert p.count(a)==1
p=p.replace(a,'''		bd.device_addr = buf->da;
		buf->fw_da = buf->da;
		if (inst->session_type == VIDC_SESSION_TYPE_ENC && (sec_types & BIT(buf->type & 0xf))) {
			dma_addr_t sda = venus_sec_np_map(core, buf->da, buf->size);

			if (sda)
				bd.device_addr = buf->fw_da = sda;
		}
		dev_info(dev, "DBG SEC: intbuf type %#x size %u da %pad fw_da %pad\\n",
			 buf->type, buf->size, &buf->da, &buf->fw_da);

		ret = hfi_session_set_buffers(inst, &bd);''')
a="\t\tbd.device_addr = buf->da;\n\t\tbd.response_required = true;"
assert p.count(a)==2
p=p.replace(a,"\t\tbd.device_addr = buf->fw_da;\n\t\tbd.response_required = true;")
a="\t\tdma_free_attrs(inst->core->dev, buf->size, buf->va, buf->da,\n\t\t\t       buf->attrs);"
n=p.count(a)
assert n>=1, n
p=p.replace(a,"\t\tif (buf->fw_da == buf->da ||\n\t\t    venus_sec_np_unmap(inst->core, buf->da, buf->fw_da, buf->size))\n\t\tdma_free_attrs(inst->core->dev, buf->size, buf->va, buf->da,\n\t\t\t       buf->attrs);\n\t\telse\n\t\t\tdev_err(inst->core->dev, \"DBG SEC: leaking a secure buffer\\n\");")
print("free sites patched:", n)
open('helpers.c','w').write(p)
