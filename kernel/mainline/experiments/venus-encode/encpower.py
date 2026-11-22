# SPDX-License-Identifier: MIT
# Summarise encpower.txt: per phase, mean battery current/power from the
# current_now samples (distinct 10 s updates only) and the QG FIFO dump.
import re, sys, statistics as st
L = open(sys.argv[1]).read().splitlines()
S = {}; P = {}; Q = {}; cur = None
for l in L:
    if l.startswith("S "):
        _, ph, t, i, v, on = l.split(); S.setdefault(ph, []).append((int(t), -int(i) / 1000, int(v) / 1e6, on))
    elif l.startswith("PHASE "):
        f = l.split(); P[f[1]] = dict(t0=int(f[2]), t1=int(f[3]), **{k: int(v) for k, v in (x.split("=") for x in f[4:])})
    elif l.startswith("QG "):
        cur = l.split()[1]; Q[cur] = {}
    elif cur:
        for a, v in re.findall(r"([0-9a-f]{4}):([0-9a-fX]{2})", l):
            if v != "XX": Q[cur][int(a, 16)] = int(v, 16)
for ph, s in S.items():
    # skip the first 20 s of a phase (previous phase's burst average)
    t0 = P[ph]["t0"]; s2 = [x for x in s if x[0] - t0 >= 20]
    # current_now repeats until the next 10 s poll: dedupe consecutive values
    d = [x for k, x in enumerate(s2) if k == 0 or x[1] != s2[k - 1][1]]
    I = [x[1] for x in d]; V = st.mean(x[2] for x in d); on = {x[3] for x in s}
    p = P[ph]; dt = p["t1"] - p["t0"]
    fps = p["frames"] / dt if p["frames"] else 0
    print(f"{ph}: {dt}s, n={len(I)} I mean {st.mean(I):.0f} mA (min {min(I):.0f}, max {max(I):.0f}), "
          f"V {V:.3f}, P {st.mean(I)*V:.0f} mW, frames {p['frames']} ({fps:.0f} fps), cpu {p['cpu_ms']/1000:.0f} s, charger online {on}")
    r = Q[ph]; w = lambda a: r[a] | r[a + 1] << 8
    ent = []
    for k in range(8):
        i = w(0x48a0 + 2 * k); i = i - 0x10000 if i & 0x8000 else i
        ent.append(f"{i * 0.305176:.0f}")
    print(f"   FIFO (mA, discharge +; index order, rt_count={r[0x480a] & 15}): {' '.join(ent)}")
