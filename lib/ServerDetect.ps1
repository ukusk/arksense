# ArkSense - lib\ServerDetect.ps1
# Finds the address the ARK client process is sending its game traffic to.
#
# ARK talks to its server over UDP, and Windows' connection tables keep no remote
# address for UDP. The kernel's own network events (ETW provider
# Microsoft-Windows-Kernel-Network) do: every UDP send carries the sending process
# id and the destination. This records a few seconds of those events with the
# built-in NetEventPacketCapture cmdlets (needs admin - ArkSense already runs
# elevated), keeps only packets ARK's process sent, and writes the destinations
# busiest first. Nothing inside the game is read or touched.
#
# Output file, one line per destination:  <ip> <port> <packets>
# or "local <ip> <port> <packets>" (only a server on this PC, 127.x), or "none" (no ARK
# traffic seen), or "error <message>".
# Run by ArkSense; can also be run by hand:
#   powershell -ExecutionPolicy Bypass -File ServerDetect.ps1 -GamePid 1234 -Out x.txt

param(
    [Parameter(Mandatory = $true)][int]$GamePid,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Seconds = 3
)

$ErrorActionPreference = 'Stop'
$session = 'ArkSenseNet'
$etl = Join-Path $env:TEMP 'ArkSense-net.etl'
$tmp = "$Out.tmp"

# write to a temp file, then rename: ArkSense never reads a half-written result
function Write-Result([string]$text) {
    Set-Content -LiteralPath $tmp -Value $text -Encoding ASCII
    Move-Item -LiteralPath $tmp -Destination $Out -Force
}

# ports arrive in network byte order when read raw
function Swap16([int]$v) { return ((($v -band 0xFF) -shl 8) -bor (($v -shr 8) -band 0xFF)) }

try {
    # a session left behind by an interrupted run would block a new one
    $old = Get-NetEventSession -Name $session -ErrorAction SilentlyContinue
    if ($old) {
        if ($old.SessionStatus -eq 'Running') { Stop-NetEventSession -Name $session }
        Remove-NetEventSession -Name $session
    }
    if (Test-Path -LiteralPath $etl) { Remove-Item -LiteralPath $etl -Force }

    New-NetEventSession -Name $session -CaptureMode SaveToFile -LocalFilePath $etl | Out-Null
    Add-NetEventProvider -Name 'Microsoft-Windows-Kernel-Network' -SessionName $session -Level 5 | Out-Null
    Start-NetEventSession -Name $session
    Start-Sleep -Seconds $Seconds
    Stop-NetEventSession -Name $session
    Remove-NetEventSession -Name $session

    # 42 = UDP send over IPv4, 58 = UDP send over IPv6
    $counts = @{}
    $local = @{}
    $seen = 0
    $fields = ''
    $events = @(Get-WinEvent -Path $etl -Oldest -ErrorAction SilentlyContinue |
                Where-Object { $_.Id -eq 42 -or $_.Id -eq 58 })
    foreach ($e in $events) {
        $seen++
        # prefer the rendered, named fields; fall back to raw positions
        $d = @{}
        try {
            $x = [xml]$e.ToXml()
            foreach ($p in $x.Event.EventData.Data) { $d[[string]$p.Name] = [string]$p.'#text' }
        } catch { }
        if ($fields -eq '') { $fields = ($d.Keys -join ',') }
        if ($d.ContainsKey('PID') -and $d.ContainsKey('daddr') -and $d.ContainsKey('dport')) {
            $procId = [int]$d['PID']
            $ip = $d['daddr']
            $port = $d['dport']
        } else {
            $procId = [int]$e.Properties[0].Value
            $raw = $e.Properties[2].Value
            if ($raw -is [byte[]]) { $ip = ([System.Net.IPAddress]::new($raw)).ToString() }
            else { $ip = ([System.Net.IPAddress]::new([long][uint32]$raw)).ToString() }
            $port = Swap16 ([int]$e.Properties[4].Value)
        }
        if ($procId -ne $GamePid) { continue }
        if ($ip -match '^\d+$') {
            # some systems render the address as a raw number
            $ip = ([System.Net.IPAddress]::new([long][uint32]$ip)).ToString()
        }
        # loopback = a server on this PC: kept apart; skip unspecified and multicast/broadcast
        if ($ip -match '^127\.' -or $ip -eq '::1') {
            $k2 = "$ip $port"
            if ($local.ContainsKey($k2)) { $local[$k2]++ } else { $local[$k2] = 1 }
            continue
        }
        if ($ip -match '^(0\.|22[4-9]\.|2[3-5][0-9]\.)') { continue }
        $key = "$ip $port"
        if ($counts.ContainsKey($key)) { $counts[$key]++ } else { $counts[$key] = 1 }
    }

    if ($counts.Count -eq 0 -and $local.Count -gt 0) {
        $best = $local.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        Write-Result "local $($best.Key) $($best.Value)"
        exit 0
    }
    if ($counts.Count -eq 0) {
        Write-Result "none ($seen UDP sends seen in total; fields: $fields)"
        exit 0
    }
    $lines = $counts.GetEnumerator() | Sort-Object Value -Descending |
             ForEach-Object { "$($_.Key) $($_.Value)" }
    Write-Result ($lines -join "`r`n")
}
catch {
    try { Stop-NetEventSession -Name $session -ErrorAction SilentlyContinue } catch { }
    try { Remove-NetEventSession -Name $session -ErrorAction SilentlyContinue } catch { }
    Write-Result ('error ' + ($_.Exception.Message -replace '[\r\n]+', ' '))
}
finally {
    if (Test-Path -LiteralPath $etl) { Remove-Item -LiteralPath $etl -Force -ErrorAction SilentlyContinue }
}
