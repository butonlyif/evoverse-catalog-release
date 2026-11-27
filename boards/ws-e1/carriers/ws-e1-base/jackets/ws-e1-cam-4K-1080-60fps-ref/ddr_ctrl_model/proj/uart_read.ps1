param([string]$Port = 'COM8', [int]$Seconds = 5)
$sp = New-Object System.IO.Ports.SerialPort($Port, 115200, 'None', 8, 'One')
$sp.ReadTimeout = 200
$sp.Open(); $sp.DiscardInBuffer()
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$sb = New-Object System.Text.StringBuilder
$buf = New-Object byte[] 1024
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
  try {
    $n = $sp.Read($buf, 0, $buf.Length)
    for ($i = 0; $i -lt $n; $i++) {
      $c = $buf[$i]
      if ($c -ge 32 -and $c -le 126) { [void]$sb.Append([char]$c) }
      elseif ($c -eq 10) { [void]$sb.Append("`n") }
      else { [void]$sb.Append('.') }
    }
  } catch { }
}
$sp.Close()
Write-Host $sb.ToString()
