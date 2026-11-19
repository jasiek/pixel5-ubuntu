#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Battery OCV tables for the mainline redfin DTB, from the phone's own DT.

    scripts/gen-battery-ocv.py firmware/live.dts [PROFILE] > battery-ocv.dtsi

qcom_qg (the PM7250B fuel gauge) needs simple-battery ocv-capacity tables.
The downstream DT carries the cell's characterisation as a QG battery profile
under /qcom,battery-data; downstream picks it by battery ID (on this phone
bms/battery_type = 82300172013, the LSN cell). This reads the profile's
discharge table, qcom,pc-temp-v2-lut (rows: state of charge in 0.01 %,
columns: degrees C, data: OCV in 100 uV), and prints the property lines
that go inside the battery node.

Vendor data: the output is generated at build time into the gitignored
build tree and never committed.
"""
import re
import sys

DEFAULT_PROFILE = "qcom,4228969_Google_R3_LSN_4000mAh"
TABLE = "qcom,pc-temp-v2-lut"


def u32_list(text, prop):
    m = re.search(prop + r" = <([^>]*)>;", text)
    if not m:
        raise SystemExit(f"{prop} not found")
    vals = [int(v, 0) for v in m.group(1).split()]
    return [v - (1 << 32) if v >= 1 << 31 else v for v in vals]


def node_body(text, name, start=0):
    """Text of the first node called `name` at or after `start`."""
    i = text.index(name + " {", start)
    depth, j = 0, text.index("{", i)
    while True:
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i:j]
        j += 1


def main():
    dts = open(sys.argv[1]).read()
    profile = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_PROFILE
    lut = node_body(node_body(dts, profile), TABLE)
    temps = u32_list(lut, "qcom,lut-col-legend")
    socs = u32_list(lut, "qcom,lut-row-legend")
    ocv = u32_list(lut, "qcom,lut-data")
    if len(ocv) != len(temps) * len(socs):
        raise SystemExit(f"{TABLE}: {len(ocv)} values, expected {len(temps)}x{len(socs)}")

    out = [f"/* {profile} {TABLE}, by scripts/gen-battery-ocv.py */",
           "ocv-capacity-celsius = <" + " ".join(f"({t})" for t in temps) + ">;"]
    for c, t in enumerate(temps):
        pairs, seen = [], set()
        for r, soc in enumerate(socs):
            pct = round(soc / 100)
            if pct in seen:     # mainline wants whole percent: keep the first
                continue
            seen.add(pct)
            pairs.append(f"<{ocv[r * len(temps) + c] * 100} {pct}>")
        out.append(f"/* {t} C */")
        out.append(f"ocv-capacity-table-{c} = " + ", ".join(pairs) + ";")
    print("\n".join(out))
    print(f"{profile}: {len(temps)} temperatures x {len(pairs)} points",
          file=sys.stderr)


main()
