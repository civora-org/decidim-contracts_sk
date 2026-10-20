#!/bin/sh
# runs inside a throwaway container; mirrors the flags proposed for the host adapter
now() { date +%s.%N; }
conv() { # conv <fmt> <infile> <outdir> [profile]
  p=${4:-/tmp/lo-$(cat /proc/sys/kernel/random/uuid)}
  s=$(now)
  env -i PATH=/usr/bin:/bin HOME=/tmp/home LANG=C.UTF-8 timeout 120 soffice --headless --norestore -env:UserInstallation=file://$p --convert-to "$1" --outdir "$3" "$2" >/tmp/lo.log 2>&1
  rc=$?
  e=$(now)
  printf '%s\t%s\trc=%s\t%.2fs\n' "$2" "$1" "$rc" "$(echo "$e - $s" | bc 2>/dev/null || awk "BEGIN{print $e-$s}")"
}
mkdir -p /tmp/home /work/out
echo "--- COLD (first soffice run in fresh container): sample.doc -> docx"
conv docx /in/sample.doc /work/out
echo "--- WARM x5 (fresh profile each): sample.doc -> docx"
for i in 1 2 3 4 5; do conv docx /in/sample.doc /work/out; done
echo "--- WARM x5 (reused profile): sample.doc -> docx"
for i in 1 2 3 4 5; do conv docx /in/sample.doc /work/out /tmp/lo-reuse; done
echo "--- sample.doc -> pdf (direct) and sample.docx -> pdf"
conv pdf /in/sample.doc /work/out
conv pdf /work/out/sample.docx /work/out/viaDocx
echo "--- synthetic docx -> pdf x3"
for f in synth-full synth-publication; do for i in 1 2 3; do conv pdf /work/$f.docx /work/out; done; done
echo "--- round trip: synthetic template docx -> doc -> docx"
mkdir -p /work/out/rt1 /work/out/rt2
conv doc /work/synthetic-template.docx /work/out/rt1
conv docx /work/out/rt1/synthetic-template.doc /work/out/rt2
echo "--- failure modes: garbage file, timeout wrapper"
echo "not a document" > /work/garbage.docx
conv pdf /work/garbage.docx /work/out/g
ls /work/out/g 2>&1 | head -2
echo "--- peak memory of one run"
/usr/bin/time -v env -i PATH=/usr/bin:/bin HOME=/tmp/home soffice --headless --norestore -env:UserInstallation=file:///tmp/lo-mem --convert-to pdf --outdir /work/out/mem /work/synth-full.docx 2>&1 | grep -E 'Maximum resident|Elapsed' || echo "no /usr/bin/time"
