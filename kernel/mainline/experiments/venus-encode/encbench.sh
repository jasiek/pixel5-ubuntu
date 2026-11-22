# SPDX-License-Identifier: MIT
# Encoder benchmark, runs on the phone: scripts/ssh.sh 'bash -s' < encbench.sh
# runs on the phone
cd /tmp
for s in 1280x720 1920x1080; do W=${s%x*}; H=${s#*x}; [ -f src$H.yuv ] || gst-launch-1.0 -q videotestsrc num-buffers=300 pattern=ball ! "video/x-raw,format=NV12,width=$W,height=$H,framerate=30/1" ! filesink location=src$H.yuv; done
ls -l src*.yuv | awk '{print $5, $9}'
bench() { # name pipeline-tail
  read u0 s0 < <(awk '/^cpu /{print $2+$3, $4}' /proc/stat); t0=$(date +%s%N)
  sudo gst-launch-1.0 -q filesrc location=src$H.yuv ! rawvideoparse width=$W height=$H format=nv12 framerate=30/1 ! video/x-raw,colorimetry=bt601 ! $2 >/tmp/gst.txt 2>&1; rc=$?
  t1=$(date +%s%N); read u1 s1 < <(awk '/^cpu /{print $2+$3, $4}' /proc/stat)
  ms=$(( (t1-t0)/1000000 )); echo "$1 ${W}x$H rc=$rc ${ms} ms = $(( 300*1000 / ms )) fps (incl. start-up), CPU $(( (u1-u0+s1-s0)*10 )) ms"; [ $rc = 0 ] || tail -2 /tmp/gst.txt
}
for s in 1280x720 1920x1080; do W=${s%x*}; H=${s#*x}
  for k in 1 2; do bench "venus run$k" "v4l2h264enc extra-controls=controls,video_bitrate=8000000 ! h264parse ! mp4mux ! filesink location=/tmp/v$H.mp4"; done
  bench "x264 veryfast" "x264enc speed-preset=veryfast bitrate=8000 ! h264parse ! mp4mux ! filesink location=/tmp/x$H.mp4"
  ls -l /tmp/v$H.mp4 /tmp/x$H.mp4 | awk '{print $5, $9}'
done
# 1 frame: start-up cost
W=1280; H=720; t0=$(date +%s%N); sudo gst-launch-1.0 -q filesrc location=src720.yuv ! rawvideoparse width=1280 height=720 format=nv12 framerate=30/1 ! video/x-raw,colorimetry=bt601 ! v4l2h264enc ! fakesink num-buffers=1 >/dev/null 2>&1; t1=$(date +%s%N); echo "venus 1 frame: $(( (t1-t0)/1000000 )) ms"
# check the 1080p result: decode both ways, count bytes, PSNR on 3 frames
sudo gst-launch-1.0 -q filesrc location=/tmp/v1080.mp4 ! qtdemux ! h264parse ! avdec_h264 ! videoconvert ! video/x-raw,format=NV12 ! filesink location=/tmp/v1080.yuv; ls -l /tmp/v1080.yuv | awk '{print $5, $9}'
python3 - <<PY
import math
W,H=1920,1080; fs=W*H*3//2; ys=W*H
a=open("/tmp/src1080.yuv","rb"); b=open("/tmp/v1080.yuv","rb")
for n in range(300):
    x=a.read(fs); y=b.read(fs)
    if n in (0,150,299):
        se=sum((p-q)*(p-q) for p,q in zip(x[:ys:11],y[:ys:11])); mse=se/len(x[:ys:11])
        print("1080p frame",n,"Y PSNR %.1f dB"%(10*math.log10(255*255/mse) if mse else 99), "len", len(y))
PY
sudo gst-launch-1.0 -q filesrc location=/tmp/v1080.mp4 ! qtdemux ! h264parse ! v4l2h264dec ! video/x-raw ! fakesink sync=false; echo "venus decode of venus encode rc=$?"
sudo gst-launch-1.0 -q filesrc location=/home/ubuntu/video/ball1080.mp4 ! qtdemux ! h264parse ! v4l2h264dec ! video/x-raw ! fakesink sync=false; echo "decoder rc=$?"
sleep 3; sudo grep -E "^mvs" /sys/kernel/debug/pm_genpd/pm_genpd_summary | awk '{print $1, $2}'
sudo dmesg | grep -v "command line" | grep -E "context fault|take back|leak|sys error|SFR|DBG SEC: (give|assign|map)" | tail -5
