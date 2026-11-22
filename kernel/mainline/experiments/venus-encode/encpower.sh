# SPDX-License-Identifier: MIT
# Encode power (Test 251). On the phone, as root, on battery (charger offline):
#   scripts/ssh.sh "cat > /tmp/encpower.sh" < encpower.sh; sudo nohup bash /tmp/encpower.sh &
# Phases of $T s: idle, Venus 1080p encode loop, x264 1080p loop, idle.
# Samples QG current_now (last burst average, refreshed every 10 s) every 2 s
# and dumps the QG FIFO (76.8 s averages) at each phase end.
T=${T:-300}; O=/tmp/encpower.txt; : > $O
P=/sys/class/power_supply; F=/sys/kernel/debug/regmap/0-02/registers
r() { dd if=$F bs=9 skip=$(($1)) count=$2 status=none | awk '{printf "%s%s ", $1, $2}'; echo; }
qgdump() { echo "QG $1 $(date +%s)" >> $O; for a in "0x480a 1" "0x4851 2" "0x4888 7" "0x4890 16" "0x48a0 16" "0x48cc 2"; do r $a >> $O; done; }
cd /tmp
enc() { gst-launch-1.0 -q filesrc location=src1080.yuv ! rawvideoparse width=1920 height=1080 format=nv12 framerate=30/1 ! video/x-raw,colorimetry=bt601 ! $1 ! h264parse ! mp4mux ! filesink location=/tmp/pw.mp4 >/dev/null 2>&1; }
phase() { # name encoder-element|-
  n=0; t0=$(date +%s); read u0 s0 < <(awk '/^cpu /{print $2+$3, $4}' /proc/stat)
  ( while [ $(( $(date +%s) - t0 )) -lt $T ]; do echo "S $1 $(date +%s) $(cat $P/qcom-qg/current_now) $(cat $P/qcom-qg/voltage_now) $(cat $P/pm8150b-charger/online)" >> $O; sleep 2; done ) &
  sp=$!
  if [ "$2" = - ]; then sleep $T; else while [ $(( $(date +%s) - t0 )) -lt $T ]; do enc "$2" && n=$((n+300)); done; fi
  wait $sp; t1=$(date +%s); read u1 s1 < <(awk '/^cpu /{print $2+$3, $4}' /proc/stat)
  echo "PHASE $1 $t0 $t1 frames=$n cpu_ms=$(( (u1-u0+s1-s0)*10 ))" >> $O; qgdump $1
}
sleep 30
phase idle1 -
phase venus "v4l2h264enc extra-controls=controls,video_bitrate=8000000"
phase x264 "x264enc speed-preset=veryfast bitrate=8000"
phase idle2 -
echo DONE >> $O
