# ============================================================================
# 脚本名称: test_udp_rx.ps1
# 功能描述: 在 PC 侧监听 UDP 端口，统计板子(ws_e1_tse, 10.0.0.8:1313)发来的
#           UDP 测试包数量、字节数、来源与载荷图案，用于板上 UDP 发送通路验证。
#           使用 .NET UdpClient 直接监听，无需管理员权限（pktmon 需要管理员，
#           本脚本不需要）。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File doc\test_udp_rx.ps1 [-Port 10005] [-Seconds 10]
#
# 前提:
#   1. PC 网卡 IP = 10.0.0.2（与固件 DST_IP 一致，见
#      embedded_sw/sapphire/bsp/efinix/EfxSapphireSoc/app/tseDemo.h）
#   2. 板子 IP = 10.0.0.8，固件 SRC_PORT=0x0521(1313) → DST_PORT=0x2715(10005)
#   3. 板子已烧写 ws_e1_tse.bit 且固件已运行（ROM 固件或 OpenOCD 加载的 ELF）
#   4. 网线已连接
#
# 预期输出示例（千兆链路，固件 TEST_MODE=0 持续发包）:
#   packets=132302 bytes=13230200 in 10s
#   from=10.0.0.8:1313 len=100
#   payload head: 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F
# ============================================================================
param(
    [int]$Port = 10005,     # 监听端口 = 固件 DST_PORT
    [int]$Seconds = 10      # 采样时长
)

$udp = New-Object System.Net.Sockets.UdpClient($Port)
$udp.Client.ReceiveTimeout = ($Seconds + 2) * 1000
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$count = 0
$bytes = 0
$first = $null
$firstFrom = ""

try {
    while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
        $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $data = $udp.Receive([ref]$ep)
        if ($count -eq 0) { $first = $data; $firstFrom = $ep.ToString() }
        $count++
        $bytes += $data.Length
    }
} catch {
    # ReceiveTimeout 到期（采样结束或无包）——正常退出循环
}
$udp.Close()

"packets=$count bytes=$bytes in ${Seconds}s"
if ($first) {
    "from=$firstFrom len=$($first.Length)"
    $head = [Math]::Min(15, $first.Length - 1)
    "payload head: " + (($first[0..$head] | ForEach-Object { $_.ToString("X2") }) -join " ")
} else {
    "NO PACKETS RECEIVED"
}
