# uart_lat_decode.ps1 — 板级延迟/B 时机/队列深度帧解码（多数票）
# 输入：uart_read.ps1 抓到的 MODE2 帧流（DDR:XXXXXXXX）
# 帧载荷 lat_word = {blk[3:0], set[1:0], kind[2:0], done, 3'h0, data[15:0]}
#   blk 0-8 = 测量块；blk 9 = 状态字 data={fail, err_tot[14:0]}
#   Phase 5（默认）：(AWCACHE,AWCOBUF) 矩阵，set 0=RD 1=WA 2=WL 3=BB，
#     kind 0=min 1=max 2=cnt 3=P50 4=P95 5=P99 6=ovf；set=3 仅 kind=2 有值
#   Phase 3（-Phase 3）：固定速率扫描，blk=INTERVAL 档 {256,128,64,32,16,8,4,2,1}，
#     set 恒 0，kind 0=rd_cyc 1=bp_cnt 2=if_peak 3=err（§8.4）
#   Phase 6（-Phase 6）：OOO 探测，blk 恒 0（9=状态字），set 恒 0，
#     kind 0=oo_cnt 1=oo_first{rid[6:4],seq[3:0]} 2=done 3=err（§8.7）
#   Phase 7（-Phase 7）：容量/别名探测，blk=探针号 0-8（9=状态字），set 恒 0，
#     kind 0=hi_err 1=alias_err 2=探针地址[15:0] 3=探针地址[32:16]（§8.8）
# 判据：仅统计 done=1 的帧（测量完成后的终态轮发）；每 key 多数票取值
param([string]$In = 'uart_p2_capture.txt', [int]$Phase = 5)

$map = @{}
$total = 0; $nodone = 0; $badfmt = 0
$stateVotes = @{}

Get-Content $In | ForEach-Object {
    if ($_ -match 'DDR:([0-9A-Fa-f]{8})') {
        $w = [Convert]::ToUInt32($Matches[1], 16)
        $total++
        $blk  = ($w -shr 28) -band 0xF
        $set  = ($w -shr 26) -band 0x3
        $kind = ($w -shr 23) -band 0x7
        $done = ($w -shr 22) -band 0x1
        $data = $w -band 0xFFFF
        if ($done -ne 1) { $nodone++; return }
        if ($blk -eq 9) {
            if ($stateVotes.ContainsKey($data)) { $stateVotes[$data]++ }
            else { $stateVotes[$data] = 1 }
            return
        }
        if ($Phase -ge 3 -and $set -ne 0) { $badfmt++; return }
        if ($Phase -eq 6 -and $blk -notin 0,9) { $badfmt++; return }
        if ($Phase -eq 7 -and $blk -notin 0..8) { $badfmt++; return }
        $key = '{0},{1},{2}' -f $blk, $set, $kind
        if (-not $map.ContainsKey($key)) { $map[$key] = @{} }
        if ($map[$key].ContainsKey($data)) { $map[$key][$data]++ }
        else { $map[$key][$data] = 1 }
    } elseif ($_ -match 'DDR:') { $badfmt++ }
}

function Top-Vote($h) {
    $best = $null; $bn = 0; $sum = 0
    foreach ($k in $h.Keys) { $sum += $h[$k]; if ($h[$k] -gt $bn) { $bn = $h[$k]; $best = $k } }
    [pscustomobject]@{ val = $best; votes = $bn; tot = $sum }
}

if ($Phase -eq 7) {
    # ---- Phase 7：容量/别名探测表（与 ddr_memcheck ad_addr_f 一致）----
    $probeTab = @(0L, 0x0FFFF000L, 0x10000000L, 0x10001000L, 0x20000000L,
                  0x40000000L, 0x80000000L, 0xFFFFF000L, 0x100000000L)
    Write-Host "==== frames: total=$total done=1 votes, nodone=$nodone, badfmt=$badfmt ===="
    Write-Host ""
    Write-Host "blk | probe addr |  hi  |  al  | verdict          (votes/total)"
    Write-Host "----+------------+------+------+----------------------------------"
    for ($b = 0; $b -lt 9; $b++) {
        $cells = @(); $vt = 0; $tt = 0
        foreach ($k in 0..3) {
            $key = '{0},0,{1}' -f $b, $k
            if ($map.ContainsKey($key)) {
                $r = Top-Vote $map[$key]
                $cells += ('{0,5}' -f $r.val)
                $vt = [Math]::Max($vt, $r.votes); $tt = [Math]::Max($tt, $r.tot)
            } else { $cells += '    -' }
        }
        # 探针地址：kind 2=[15:0] kind 3=[31:16]（bit32 不入 16 位报告，
        # 探针 8 显示低 32 位；报告自证，缺数据用表值）
        if ($cells[2] -ne '    -' -and $cells[3] -ne '    -') {
            $pa = ([long]$cells[3]) * 65536L + [long]$cells[2]
        } else { $pa = $probeTab[$b] }
        if ($cells[0] -eq '    -') {
            $v = 'no data'
        } elseif ([int]$cells[0] -eq 0 -and [int]$cells[1] -eq 0) {
            $v = if ($b -le 1) { 'accessible (alias n/a)' } else { 'WRAP-ALIAS (hi masked)' }
        } elseif ([int]$cells[0] -eq 0) {
            $v = 'accessible, no pollution'
        } elseif ([int]$cells[1] -gt 0) {
            $v = 'not-accessible (SLVERR)'
        } else {
            $v = 'not-accessible (no poll)'
        }
        Write-Host ("{0,3} | 0x{1,7:X} | {2} | {3} | {4}  ({5}/{6})" -f `
            $b, $pa, $cells[0], $cells[1], $v, $vt, $tt)
    }
} elseif ($Phase -eq 6) {
    # ---- Phase 6：OOO 探测（blk 恒 0，kind 0=oo_cnt 1=first 2=done 3=err）----
    Write-Host "==== frames: total=$total done=1 votes, nodone=$nodone, badfmt=$badfmt ===="
    Write-Host ""
    $cells = @(); $vt = 0; $tt = 0
    foreach ($k in 0..3) {
        $key = '0,0,{0}' -f $k
        if ($map.ContainsKey($key)) {
            $r = Top-Vote $map[$key]
            $cells += ('{0,5}' -f $r.val)
            $vt = [Math]::Max($vt, $r.votes); $tt = [Math]::Max($tt, $r.tot)
        } else { $cells += '    -' }
    }
    $frid = (([int]$cells[1]) -shr 4) -band 0x7
    $fseq = ([int]$cells[1]) -band 0xF
    Write-Host "oo_cnt | first{rid,seq} | done | err   (votes/total)"
    Write-Host "-------+----------------+------+--------------------"
    Write-Host ("{0} | rid={1} seq={2}  | {3} | {4}  ({5}/{6})" -f `
        $cells[0], $frid, $fseq, $cells[2], $cells[3], $vt, $tt)
    if ($cells[0] -eq '    -') {
        Write-Host "verdict: no data (missing kind=0 frames)"
    } elseif ([int]$cells[0] -eq 0) {
        Write-Host "verdict: in-order completion (oo_cnt=0) -> OUT_OF_ORDER_ENABLE=0 holds"
    } else {
        Write-Host "verdict: OUT-OF-ORDER detected (oo_cnt>0) -> OUT_OF_ORDER_ENABLE=1 candidate"
    }
} elseif ($Phase -eq 3) {
    # ---- Phase 3：固定速率扫描表（与 ddr_memcheck qd_ivl_f 一致）----
    $ivlTab = @(256, 128, 64, 32, 16, 8, 4, 2, 1)
    $kindName = @('cyc', 'bp', 'ifp', 'err')
    Write-Host "==== frames: total=$total done=1 votes, nodone=$nodone, badfmt=$badfmt ===="
    Write-Host ""
    Write-Host "blk |  ivl |  cyc  |   bp  |  ifp  |  err   (votes/total)"
    Write-Host "----+------+-------+-------+-------+----------------------"
    for ($b = 0; $b -lt 9; $b++) {
        $cells = @(); $vt = 0; $tt = 0
        foreach ($k in 0..3) {
            $key = '{0},0,{1}' -f $b, $k
            if ($map.ContainsKey($key)) {
                $r = Top-Vote $map[$key]
                $cells += ('{0,5}' -f $r.val)
                $vt = [Math]::Max($vt, $r.votes); $tt = [Math]::Max($tt, $r.tot)
            } else { $cells += '    -' }
        }
        Write-Host ("{0,3} | {1,4} | {2}  ({3}/{4})" -f `
            $b, $ivlTab[$b], ($cells -join '|'), $vt, $tt)
        Write-Host "----+------+-------+-------+-------+----------------------"
    }
} else {
    # ---- Phase 5：B 时机矩阵（与 ddr_memcheck blk_cache_f/blk_cobuf_f 一致）----
    $kindName = @('min', 'max', 'cnt', 'P50', 'P95', 'P99', 'ovf')
    $cacheTab = @('0000', '0000', '0001', '0010', '0011', '0100', '0111', '1110', '1110')
    $cobufTab = @(0, 1, 0, 0, 0, 0, 0, 0, 1)

    Write-Host "==== frames: total=$total done=1 votes, nodone=$nodone, badfmt=$badfmt ===="
    Write-Host ""
    Write-Host "blk | cache | cobuf | set  |  min  max  cnt   P50  P95  P99  ovf   (votes/total)"
    Write-Host "----+-------+-------+------+--------------------------------------------"

    for ($b = 0; $b -lt 9; $b++) {
        foreach ($s in 0..3) {
            $cells = @(); $vt = 0; $tt = 0
            foreach ($k in 0..6) {
                $key = '{0},{1},{2}' -f $b, $s, $k
                if ($map.ContainsKey($key)) {
                    $r = Top-Vote $map[$key]
                    $cells += ('{0,4}' -f $r.val)
                    $vt = [Math]::Max($vt, $r.votes); $tt = [Math]::Max($tt, $r.tot)
                } else { $cells += '   -' }
            }
            $tag = switch ($s) { 0 { 'RD ' } 1 { 'WA ' } 2 { 'WL ' } default { 'BB ' } }
            Write-Host ("{0,3} | {1} | {2,5} | {3}  | {4}  ({5}/{6})" -f `
                $b, $cacheTab[$b], $cobufTab[$b], $tag, ($cells -join ' '), $vt, $tt)
        }
        Write-Host "----+-------+-------+------+--------------------------------------------"
    }
}

Write-Host ""
foreach ($d in $stateVotes.Keys) {
    $fail = ($d -shr 15) -band 0x1
    $etot = $d -band 0x7FFF
    Write-Host ("state blk9: fail={0} err_tot(mod 32768)={1}  votes={2}" -f $fail, $etot, $stateVotes[$d])
}
