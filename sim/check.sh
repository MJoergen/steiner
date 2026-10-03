#!/bin/bash
# Checks one parameter set: sim/check.sh T K N, run by "make check" after it has built
# steiner_tb and steiner2uart_tb. The solutions must be exactly those of the reference
# model, in the same order, and those in the results file, if there is one. The text
# from steiner2uart.vhd must be exactly that of the reference model.

set -u
t=$1 k=$2 n=$3
p=${t}_${k}_${n}

echo "Checking (t, k, n) = ($t, $k, $n)"

run() {   # run <testbench> <output file> <log file>
  ghdl -r --std=08 "$1" -gG_T="$t" -gG_K="$k" -gG_N="$n" -gG_OUTPUT="$2" \
    --assert-level=error > "$3" 2>&1 || { tail -5 "$3"; exit 1; }
}

run steiner_tb check_$p.txt check_$p.log
python3 steiner_ref.py "$t" "$k" "$n" > check_$p.ref
diff check_$p.txt check_$p.ref > /dev/null || {
  echo "The solutions differ from steiner_ref.py"; exit 1; }
if [ -f result_$p.txt ]; then
  diff check_$p.txt result_$p.txt > /dev/null || {
    echo "The solutions differ from result_$p.txt"; exit 1; }
fi

run steiner2uart_tb check_text_$p.txt check_text_$p.log
python3 steiner_ref.py --text "$t" "$k" "$n" > check_text_$p.ref
diff check_text_$p.txt check_text_$p.ref > /dev/null || {
  echo "The text from steiner2uart.vhd differs from steiner_ref.py"; exit 1; }
