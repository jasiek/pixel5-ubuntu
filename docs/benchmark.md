<!-- SPDX-License-Identifier: MIT -->
# Benchmark: what this phone is good for (2026-11-20)

Measured in Test 137 (`docs/log.md`) with `scripts/phone/pixel5-bench`, on a
fresh P7.2 install running mainline `gdadf8b4adcdb`. The phone sat on a desk with
its back cover on and USB connected.

**Verdict:** a fast, silent ARM64 home server with a built-in battery as backup
power. In CPU it beats a Raspberry Pi 5, and its storage is much faster than any
Pi. One thing needs fixing first: nothing slows the CPU down when it gets hot
(see below).

## Results

| Area | Result | Rough comparison (approximate, from public Pi results) |
|---|---|---|
| CPU, all 8 cores (7-Zip) | **14,651 MIPS** | Pi 5 ≈ 11k, Pi 4 ≈ 5.5k |
| CPU, one fast core (7-Zip) | 3,234 MIPS | about the same as one Pi 5 core |
| Encryption (AES-256-GCM, 1 core) | **1.9 GB/s** | VPN and HTTPS speed is limited by wifi, not the CPU |
| RAM | 8 GB, 29 GiB/s | twice a Pi 5 4 GB |
| Storage (UFS) | **982 MB/s read, 464 MB/s write, 43k–60k random IOPS** | about 10× a Pi on an SD card; above a Pi 5 with NVMe |
| Wifi (5 GHz, 2×2) | **~305 Mbit/s** real download | |
| USB network | ~35 MB/s | |
| 5 min at 100% on all cores | stayed at full clock, 36 → 64 °C | |
| Extra power at full load | ~2–3 W (rough measurement) | |

Full numbers, including per-core sysbench, SHA-256, Ed25519 and memory read and
write, are in Test 137.

## What it's good for

1. **Always-on home server.** Pi-hole or AdGuard, Home Assistant, Syncthing,
   Gitea, or a WireGuard/Tailscale exit node. The battery keeps it running
   through power cuts.
2. **ARM64 build or CI runner.** 8 cores, fast disk, and 103 GB free.
3. **Sensor logger.** The barometer, light sensor and accelerometer already
   work (`pixel5-see read pressure`), so it could be a small weather or room
   monitor.
4. **Small local AI models.** 8 GB of RAM fits 1–3B models. Speed not measured
   yet.

**Not good for yet:** anything that needs the screen, audio or camera, because
those don't work yet. The GPU driver loads (`/dev/dri/renderD128`), but it has
not been benchmarked.

## Fix before running long heavy loads

The CPU thermal zones have only one limit: an emergency shutdown at 110 °C.
There are no lower limits that slow the CPU when it gets hot, so the cooling
devices (`cpufreq-cpu0/6/7`, GPU devfreq) are never used. In the 5-minute test
the CPU reached 64 °C and was still slowly climbing. A long build in a warm room
would keep heating until the phone powers off. Fix: copy the downstream
throttle temperatures into our device tree.

## Notes

- To run the benchmark, `sysbench p7zip-full fio stress-ng iperf3` were
  installed on the phone with apt. A fresh image does not have them.
- The Pi numbers are approximate figures from public results, not measured
  here.
