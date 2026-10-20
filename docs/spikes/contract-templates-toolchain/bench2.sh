#!/bin/sh
F="env -i PATH=/usr/bin:/bin HOME=/tmp/home LANG=C.UTF-8"
mkdir -p /tmp/home /work/out2
echo "--- docx -> docx through LO: do =MERGEFIELDs survive?"
$F soffice --headless --norestore -env:UserInstallation=file:///tmp/lo-a --convert-to docx --outdir /work/out2/dd /work/synthetic-template.docx >/dev/null 2>&1
cd /work/out2/dd && unzip -qo synthetic-template.docx -d x && grep -o 'MERGEFIELD [^<]*' x/word/document.xml | sort | uniq -c | sort -rn | head -6
echo "--- timeout kill: does the soffice.bin child die?"
cd /work
$F timeout -s KILL 0.2 soffice --headless --norestore -env:UserInstallation=file:///tmp/lo-k --convert-to pdf --outdir /work/out2/k /work/synth-full.docx >/dev/null 2>&1; echo "wrapper rc=$?"
sleep 1; ps -eo pid,comm | grep -c '[s]office.bin' | sed 's/^/orphan soffice.bin processes after timeout -s KILL: /'
pkill -9 soffice.bin 2>/dev/null
echo "--- timeout kill with process group (setsid + kill -- -pgid)"
setsid $F soffice --headless --norestore -env:UserInstallation=file:///tmp/lo-k2 --convert-to pdf --outdir /work/out2/k2 /work/synth-full.docx >/dev/null 2>&1 &
sleep 0.15; kill -KILL -- -$! 2>/dev/null; sleep 1
ps -eo pid,comm | grep -c '[s]office.bin' | sed 's/^/orphans after process-group kill: /'
pkill -9 soffice.bin 2>/dev/null
echo "--- parallel x4, distinct profiles"
s=$(date +%s.%N)
for i in 1 2 3 4; do $F soffice --headless --norestore -env:UserInstallation=file:///tmp/lo-p$i --convert-to pdf --outdir /work/out2/par$i /work/synth-full.docx >/dev/null 2>&1 & done; wait
e=$(date +%s.%N); awk "BEGIN{printf \"4 parallel conversions: %.2fs wall; outputs: \", $e-$s}"; ls /work/out2/par*/synth-full.pdf | wc -l
echo "--- parallel x2, SAME profile"
rm -rf /tmp/lo-same
for i in 1 2; do $F soffice --headless --norestore -env:UserInstallation=file:///tmp/lo-same --convert-to pdf --outdir /work/out2/same$i /work/synth-full.docx >/dev/null 2>&1 & done; wait
ls /work/out2/same*/synth-full.pdf 2>/dev/null | wc -l | sed 's/^/shared profile, outputs produced (of 2): /'
echo "--- peak memory (cgroup) after a conversion"
cat /sys/fs/cgroup/memory.peak 2>/dev/null | awk '{printf "container memory.peak: %.0f MB (includes page cache)\n", $1/1048576}'
