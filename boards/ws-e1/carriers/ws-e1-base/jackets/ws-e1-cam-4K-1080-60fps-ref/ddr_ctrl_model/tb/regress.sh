#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ddr_ctrl_model 主回归（traceability 基线，Phase 8 定稿 2026-10-23）
#
# 用法（Git Bash / Linux，Questa vlog/vsim 需在 PATH）:
#   cd ddr_ctrl_model/tb && bash regress.sh
#
# 内容:
#   1) 全量编译 RTL + TB 到 work 库
#   2) 按 testlist.txt 逐用例仿真（tb_top 48 + tb_top_cdc 9 + tb_unit 3 = 60 项）
#   3) 汇总 PASS/FAIL，任一 FAIL 则退出码 1
#
# 日志: regress_logs/<test>.log（unit 用例为 tb_unit_*.log）
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")"

# Questa 不在 PATH 时: QUESTA_BIN 指向 win64 目录，或依赖下方本机安装路径 fallback
if ! command -v vsim >/dev/null 2>&1; then
  [ -n "${QUESTA_BIN:-}" ] && export PATH="$QUESTA_BIN:$PATH"
  # 本机 fallback: Git Bash 挂载点 / WSL 挂载点（Questa 2024.2 默认安装位）
  [ -d /d/questasim64_2024.2/win64 ] && export PATH="/d/questasim64_2024.2/win64:$PATH"
  [ -d /mnt/d/questasim64_2024.2/win64 ] && export PATH="/mnt/d/questasim64_2024.2/win64:$PATH"
fi
# WSL 互操作: 只能按全名调 vsim.exe，包装成 vsim/vlog/vlib 函数
if ! command -v vsim >/dev/null 2>&1 && command -v vsim.exe >/dev/null 2>&1; then
  vsim()    { vsim.exe "$@"; }
  vlog()    { vlog.exe "$@"; }
  vlib()    { vlib.exe "$@"; }
  export -f vsim vlog vlib 2>/dev/null || true
fi
command -v vsim >/dev/null 2>&1 || command -v vsim.exe >/dev/null 2>&1 || \
  { echo "vsim not found; set QUESTA_BIN=<questa win64 dir>"; exit 1; }

mkdir -p regress_logs

echo "== compile =="
vlib work >/dev/null 2>&1
vlog -sv -work work \
  ../rtl/ddr_model_pkg.sv \
  ../rtl/ddr_fifo.sv \
  ../rtl/ddr_async_fifo.sv \
  ../rtl/mem_model.sv \
  ../rtl/core_scheduler.sv \
  ../rtl/cfg_ctrl_fsm.sv \
  ../rtl/axi_port_shell.sv \
  ../rtl/axi_port_shell_cdc.sv \
  ../rtl/ddr_model_assertions.sv \
  ../rtl/ddr_model_if.sv \
  ../rtl/ddr_axi_model_top.sv \
  tb_pkg.sv axi_master_bfm.sv tb_scoreboard.sv \
  tb_top.sv tb_top_cdc.sv \
  tb_unit_addr.sv tb_unit_cfg.sv tb_unit_mem.sv \
  || { echo "COMPILE FAIL"; exit 1; }

run_case() { # $1=top $2=test $3=extra_args
  local top="$1" test="$2" extra="$3" log top_args
  if [ -n "$test" ]; then
    log="regress_logs/${test}.log"
    top_args="+TEST=$test"
  else
    log="regress_logs/${top}.log"
    top_args=""
  fi
  # shellcheck disable=SC2086
  # stdin 重定向到 /dev/null: 防止 vsim 吃掉 while 循环正在读的 testlist.txt
  vsim -c $top_args $extra -do "run -all; quit -f" "work.$top" -l "$log" >/dev/null 2>&1 </dev/null
  if grep -q "TEST .* PASS" "$log" 2>/dev/null; then
    echo "PASS  ${test:-$top}"
  else
    echo "FAIL  ${test:-$top}   ($log)"
    return 1
  fi
}

echo "== regress =="
pass=0; fail=0
while IFS='|' read -r top test extra; do
  [ -z "$top" ] && continue
  case "$top" in \#*) continue ;; esac
  if run_case "$top" "$test" "$extra"; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
  fi
done < testlist.txt

echo "== summary: $pass pass, $fail fail =="
[ "$fail" -eq 0 ]
