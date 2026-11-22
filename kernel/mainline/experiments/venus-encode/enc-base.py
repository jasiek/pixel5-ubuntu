# SPDX-License-Identifier: GPL-2.0-only
# Venus source edit (run inside drivers/media/platform/qcom/venus): re-enable the
# encoder and power vcodec1 (CVP core) with vcodec0. E1=1 keeps vcodec1 under software
# control (Tests 217-234: CVP never becomes active, VPSS stalls); unset for the working setup.
# Common: re-enable the encoder with MVS1 powered with vcodec0 (flag), as in release g564c192799e6.
import os
h=open('core.h').read()
a='\tconst struct firmware_version *min_fw;\n};'
assert h.count(a)==1
h=h.replace(a,'\tconst struct firmware_version *min_fw;\n\tbool vcodec1_with_vcodec0;\n};'); open('core.h','w').write(h)
c=open('core.c').read()
i=c.index('static const struct venus_resources sm7250_res'); j=c.index('};',i)
blk=c[i:j]
blk=blk.replace('\t.vcodec0_clks = { "vcodec0_core", "vcodec0_bus" },\n','\t.vcodec0_clks = { "vcodec0_core", "vcodec0_bus" },\n\t.vcodec1_clks = { "vcodec1_core", "vcodec1_bus" },\n')
blk=blk.replace('{ "venus", "vcodec0" },\n\t.vcodec_pmdomains_num = 2,','{ "venus", "vcodec0", "vcodec1" },\n\t.vcodec_pmdomains_num = 3,')
blk=blk.replace('\t.vcodec_num = 1,\n','\t.vcodec_num = 1,\n\t.vcodec1_with_vcodec0 = true,\n')
blk=blk.replace('\t.dec_nodename = "video-decoder",\n','\t.dec_nodename = "video-decoder",\n\t.enc_nodename = "video-encoder",\n')
assert blk.count('vcodec1')>=4 and 'enc_nodename' in blk, blk
c=c[:i]+blk+c[j:]; open('core.c','w').write(c)
p=open('pm_helpers.c').read()
for fn in ('static int poweroff_coreid(struct venus_core *core, unsigned int coreid_mask)\n{\n\tint ret;\n',
           'static int poweron_coreid(struct venus_core *core, unsigned int coreid_mask)\n{\n\tint ret;\n'):
    assert p.count(fn)==1
    p=p.replace(fn, fn+'\n\tif (core->res->vcodec1_with_vcodec0 && (coreid_mask & VIDC_CORE_ID_1))\n\t\tcoreid_mask |= VIDC_CORE_ID_2;\n')
open('pm_helpers.c','w').write(p)
if os.environ.get('E1')=='1':
    p=open('pm_helpers.c').read()
    old='''		ret = vcodec_clks_enable(core, core->vcodec1_clks);
		if (ret)
			return ret;

		ret = vcodec_control_v4(core, VIDC_CORE_ID_2, false);
		if (ret < 0)
			return ret;'''
    assert p.count(old)==1
    p=p.replace(old,'''		ret = vcodec_clks_enable(core, core->vcodec1_clks);
		if (ret)
			return ret;

		dev_info(core->dev, "DBG E1: vcodec1 stays under SW control\\n");''')
    open('pm_helpers.c','w').write(p)
