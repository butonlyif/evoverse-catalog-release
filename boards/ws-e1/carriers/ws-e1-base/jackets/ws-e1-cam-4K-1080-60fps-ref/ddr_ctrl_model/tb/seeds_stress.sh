#!/usr/bin/env bash
# random_stress 多 seed 扫描（Phase 8 附证）: -sv_seed 2..51 共 50 个
# 用法: bash seeds_stress.sh   （在 tb/ 下执行；Questa PATH 自寻，同 regress.sh）
set -u
cd "$(dirname "$0")"
if ! command -v vsim.exe >/dev/null 2>&1; then
  export PATH="/mnt/d/questasim64_2024.2/win64:/d/questasim64_2024.2/win64:$PATH"
fi
pass=0; fail=0
for n in $(seq 2 51); do
  log="regress_logs/random_stress_s$n.log"
  vsim.exe -c +TEST=random_stress -sv_seed "$n" -do "run -all; quit -f" \
    work.tb_top -l "$log" >/dev/null 2>&1 </dev/null
  if grep -q "TEST random_stress PASS" "$log" 2>/dev/null; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); echo "FAIL seed=$n ($log)"
  fi
done
echo "random_stress seeds 2..51: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
