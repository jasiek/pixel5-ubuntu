#!/bin/sh
# SPDX-License-Identifier: MIT
# Regenerate the raw S6E3HC2 panel driver that local patch 0004
# (kernel/mainline/patches/0004-LOCAL-drm-panel-add-the-Samsung-S6E3HC2-*)
# was made from, with linux-mdss-dsi-panel-driver-generator
# (external/lmdpdg, GPL-2.0) and the GPL downstream panel source in
# external/kernel-redbull. No phone data: the generator gets a minimal tree
# around the source .dtsi (the redfin board overrides: TE GPIO 10, reset
# pm7250b GPIO 5, supplies vddio/vdd).
#   scripts/gen-panel-driver.sh   -> build/panel-src/s6e3hc2_dvt_dsc_1080p_cmd/
# The patch then renames it, sets compatible "samsung,s6e3hc2" and lowers
# the default brightness (see the patch description).
set -eu
cd "$(dirname "$0")/.."
O=build/panel-src
mkdir -p "$O"
cat > "$O/wrap.dts" <<'DTS'
/dts-v1/;
/ {
	tlmm: tlmm { gpio-controller; #gpio-cells = <2>; };
	pm7250b_gpios: pm7250b-gpios { gpio-controller; #gpio-cells = <2>; };
	dsi_panel_pwr_supply_redbull: supplies { };
	mdss_mdp: mdp { compatible = "qcom,mdss_mdp"; };
};
#include "dsi-panel-s6e3hc2-dvt-dsc-1080p-cmd.dtsi"
&dsi_s6e3hc2_dvt_dsc_1080p_cmd {
	qcom,panel-supply-entries = <&dsi_panel_pwr_supply_redbull>;
	qcom,platform-te-gpio = <&tlmm 10 0>;
	qcom,platform-reset-gpio = <&pm7250b_gpios 5 0>;
};
DTS
docker run --rm --platform linux/arm64 \
    -v "$PWD/external/lmdpdg:/g:ro" \
    -v "$PWD/external/kernel-redbull/arch/arm64/boot/dts/google:/dts:ro" \
    -v "$PWD/$O:/out" ubuntu:24.04 sh -c '
    apt-get -qq update >/dev/null &&
    apt-get -qq install -y python3-libfdt device-tree-compiler cpp >/dev/null 2>&1 &&
    cd /out &&
    cpp -nostdinc -undef -x assembler-with-cpp -P -I /dts wrap.dts > wrap.pp.dts &&
    dtc -q -I dts -O dtb -o panel.dtb wrap.pp.dts &&
    python3 /g/lmdpdg.py -r vddio -r vdd panel.dtb'
