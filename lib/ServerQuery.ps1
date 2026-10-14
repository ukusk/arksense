# ArkSense - lib\ServerQuery.ps1
# Measures how fast the ARK *server program* answers, once a second.
#
# A plain ping (ICMP) is answered by the server machine's operating system the
# instant it arrives, however busy the game is - so it cannot see server lag. A
# Steam server query (A2S_INFO, the packet server browsers send) is answered by the
# game server process itself, so when the server is overloaded and slow, this time
# goes up with it. Nothing inside the game client is read; this only talks to the
# server's public query port, like a server browser.
#
# Query port: -QueryPort if given; otherwise looked up in Steam's server list and on
# BattleMetrics by address and game port; otherwise the usual ARK query ports are
# tried once each. Any port that answers on this address will do for timing.
#
# Output file, rewritten every second (temp file + rename):
#   line 1:  port <queryport> <how>      or   port 0 <reason>
#   line 2:  last 60 response times in ms, comma separated, -1 = no answer
#   line 3:  players <online> <max>   from the server's own A2S_INFO reply (live, once
#            a second; -1 -1 = no info reply in the last 10 s, or the query port could
#            only be matched to another server on the same machine)
#   line 4:  seen <every server found on this address: q<query>=g<game> players name; ...>
#   line 1's <how>: manual | matched (game port in its reply = ours) | listed (Steam /
#            BattleMetrics list it for our game port) | other-server (timing only)
# Exits by itself when the ArkSense process (-Parent) is gone.

param(
    [Parameter(Mandatory = $true)][string]$Ip,
    [int]$GamePort = 0,
    [int]$QueryPort = 0,
    [Parameter(Mandatory = $true)][string]$Out,
    [Parameter(Mandatory = $true)][int]$Parent
)

$ErrorActionPreference = 'Stop'
$tmp = "$Out.tmp"

function Write-Out([string]$head, [string]$samples) {
    try {
        Set-Content -LiteralPath $tmp -Value ($head + "`r`n" + $samples) -Encoding ASCII
        Move-Item -LiteralPath $tmp -Destination $Out -Force
    } catch { }     # ArkSense may be reading it right now; next second retries
}

# A2S_INFO request: FF FF FF FF 'T' "Source Engine Query" 00 [+ 4-byte challenge]
$base = [byte[]](0xFF, 0xFF, 0xFF, 0xFF, 0x54) + [System.Text.Encoding]::ASCII.GetBytes('Source Engine Query') + [byte[]](0x00)

$script:challenge = $null
$script:players = -1; $script:maxp = -1; $script:infoAt = 0
$script:verified = $false        # the query port is OUR server (its game port matches)

# A2S_INFO reply: FF FF FF FF 'I' protocol name\0 map\0 folder\0 game\0 appid(2)
# players maxp bots type env visibility vac version\0 [EDF [port(2) if EDF & 0x80]]
# -> @{ name; map; players; maxp; gameport (-1 if not sent) }
function Read-Info([byte[]]$b) {
    $i = 6
    $strs = @()
    for ($k = 0; $k -lt 4; $k++) {
        $st = $i
        while ($i -lt $b.Length -and $b[$i] -ne 0) { $i++ }
        $strs += [System.Text.Encoding]::UTF8.GetString($b, $st, [Math]::Max(0, $i - $st))
        $i++
    }
    $i += 2                                            # app id
    if ($i + 1 -ge $b.Length) { return $null }
    $info = @{ name = $strs[0]; map = $strs[1]; players = [int]$b[$i]; maxp = [int]$b[$i + 1]; gameport = -1 }
    $i += 7                                            # players maxp bots type env visibility vac
    while ($i -lt $b.Length -and $b[$i] -ne 0) { $i++ }   # version string
    $i++
    if ($i -lt $b.Length) {
        $edf = $b[$i]; $i++
        if (($edf -band 0x80) -and $i + 1 -lt $b.Length) { $info.gameport = [int]$b[$i] + 256 * [int]$b[$i + 1] }
    }
    return $info
}

# One timed query to the chosen port. Returns the reply time in ms, or -1. Any reply
# counts - a challenge (0x41) is also sent by the server program - and its token is
# kept for next time. Info replies also refresh the player count (verified port only).
function Measure-Query([string]$addr, [int]$port, [int]$timeoutMs) {
    $u = New-Object System.Net.Sockets.UdpClient
    try {
        $u.Client.ReceiveTimeout = $timeoutMs
        $u.Connect($addr, $port)
        $req = $base
        if ($script:challenge) { $req = $base + $script:challenge }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        [void]$u.Send($req, $req.Length)
        $ep = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any, 0)
        $resp = $u.Receive([ref]$ep)
        $sw.Stop()
        if ($resp.Length -ge 12 -and $resp[4] -eq 0x49 -and $script:verified) {
            try {
                $inf = Read-Info $resp
                if ($inf) { $script:players = $inf.players; $script:maxp = $inf.maxp; $script:infoAt = [Environment]::TickCount }
            } catch { }
        }
        if ($resp.Length -ge 9 -and $resp[4] -eq 0x41) {
            $script:challenge = [byte[]]$resp[5..8]
        }
        if ($resp.Length -ge 5 -and ($resp[4] -eq 0x49 -or $resp[4] -eq 0x41)) {
            return [int][Math]::Round($sw.Elapsed.TotalMilliseconds)
        }
        return -1
    } catch {
        return -1
    } finally {
        $u.Close()
    }
}

# Ask many ports at once (one socket, all sent together, replies collected for ~2 s,
# challenges answered). Returns port -> info for every server that answered.
function Scan-Ports([string]$addr, [int[]]$ports) {
    $found = @{}
    $u = New-Object System.Net.Sockets.UdpClient 0
    try {
        $ipa = [System.Net.IPAddress]::Parse($addr)
        foreach ($p in $ports) {
            try { [void]$u.Send($base, $base.Length, (New-Object System.Net.IPEndPoint ($ipa, $p))) } catch { }
        }
        $u.Client.ReceiveTimeout = 250
        $end = [Environment]::TickCount + 2200
        while ([Environment]::TickCount -lt $end) {
            try {
                $ep = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any, 0)
                $r = $u.Receive([ref]$ep)
            } catch { continue }
            if ($r.Length -lt 5) { continue }
            $from = $ep.Port
            if ($r[4] -eq 0x41 -and $r.Length -ge 9) {           # challenge: ask again with it
                $req = $base + [byte[]]$r[5..8]
                try { [void]$u.Send($req, $req.Length, (New-Object System.Net.IPEndPoint ($ipa, $from))) } catch { }
                if (-not $found.ContainsKey($from)) { $found[$from] = $null }
            } elseif ($r[4] -eq 0x49) {
                try { $found[$from] = Read-Info $r } catch { }
            }
        }
    } finally { $u.Close() }
    return $found
}

# ---- find the query port ---------------------------------------------------------
# A machine like FusionPvP's runs several ARK servers on one address, each with its own
# query port. Timing works with any of them, but the PLAYER COUNT must come from the
# server you are on: its info reply carries its game port, which must match the port
# ARK talks to (ServerDetect's port is the game port or game port + 1).
$how = 'manual'
$near = @()
if ($GamePort -gt 0) { $near = @($GamePort, ($GamePort - 1), ($GamePort + 1)) }
$cands = New-Object System.Collections.Generic.List[int]
$steamMatch = 0
$seen = ''
if ($QueryPort -gt 0) {
    $script:verified = $true                                  # you entered it yourself
} else {
    $how = ''
    # 1) Steam's own server list for this address (public, no key): addr = ip:queryport
    try {
        $r = Invoke-RestMethod -Uri ('https://api.steampowered.com/ISteamApps/GetServersAtAddress/v0001/?addr=' + $Ip) -TimeoutSec 10
        foreach ($s in @($r.response.servers)) {
            $qp = [int](([string]$s.addr).Split(':')[-1])
            if ($qp -gt 0 -and -not $cands.Contains($qp)) { $cands.Add($qp) }
            if ($steamMatch -eq 0 -and $near -contains [int]$s.gameport) { $steamMatch = $qp }
        }
    } catch { }
    # 2) BattleMetrics (browser user agent, or it answers 403)
    try {
        $url = 'https://api.battlemetrics.com/servers?filter%5Bgame%5D=ark&filter%5Bsearch%5D=' +
               $Ip + '&page%5Bsize%5D=100'
        $r = Invoke-RestMethod -Uri $url -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' -TimeoutSec 10
        foreach ($a in @($r.data | ForEach-Object { $_.attributes } | Where-Object { [string]$_.ip -eq $Ip })) {
            $qp = [int]$a.portQuery
            if ($qp -gt 0 -and -not $cands.Contains($qp)) { $cands.Add($qp) }
            if ($steamMatch -eq 0 -and $near -contains [int]$a.port) { $steamMatch = $qp }
        }
    } catch { }
    # 3) the usual places: around the game port, and ARK's default range
    $guess = @()
    if ($GamePort -gt 0) {
        $guess += ($GamePort - 3)..($GamePort + 3)
        $guess += ($GamePort + 19237), ($GamePort + 19238), ($GamePort + 19239)
    }
    $guess += 27015..27070
    foreach ($p in $guess) { if ($p -gt 0 -and $p -le 65535 -and -not $cands.Contains($p)) { $cands.Add($p) } }

    $found = Scan-Ports $Ip ([int[]]$cands.ToArray())
    # pick: the server whose game port is ours (exact, then -1, then +1)
    foreach ($gp in $near) {
        foreach ($k in $found.Keys) {
            $inf = $found[$k]
            if ($inf -and $inf.gameport -eq $gp) { $QueryPort = [int]$k; $how = 'matched'; $script:verified = $true; break }
        }
        if ($QueryPort -gt 0) { break }
    }
    # else the one Steam / BattleMetrics list for our game port
    if ($QueryPort -le 0 -and $steamMatch -gt 0 -and $found.ContainsKey($steamMatch)) {
        $QueryPort = $steamMatch; $how = 'listed'; $script:verified = $true
    }
    # else any answering port: fine for timing, but its player count may be another server's
    if ($QueryPort -le 0 -and $found.Count -gt 0) {
        $QueryPort = [int](@($found.Keys | Sort-Object)[0]); $how = 'other-server'
    }
    foreach ($k in ($found.Keys | Sort-Object)) {
        $inf = $found[$k]
        if ($inf) { $seen += "q$k=g$($inf.gameport) $($inf.players)/$($inf.maxp) $($inf.name -replace '[;\r\n\t]', ' '); " }
        else { $seen += "q$k=?; " }
    }
}
if ($QueryPort -le 0) {
    Write-Out 'port 0 query port not found - enter it on the Overlay tab' ''
    # keep the result visible for ArkSense, then leave
    while (Get-Process -Id $Parent -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 30 }
    exit 0
}
$seen = $seen.Trim()
if ($seen.Length -gt 900) { $seen = $seen.Substring(0, 900) }

# ---- measure once a second ---------------------------------------------------------
$hist = New-Object System.Collections.Generic.List[int]
while (Get-Process -Id $Parent -ErrorAction SilentlyContinue) {
    $t0 = [Environment]::TickCount
    $v = Measure-Query $Ip $QueryPort 1000
    $hist.Add($v)
    while ($hist.Count -gt 60) { $hist.RemoveAt(0) }
    $pl = if ($script:verified -and [Environment]::TickCount - $script:infoAt -lt 10000) { "players $($script:players) $($script:maxp)" } else { 'players -1 -1' }
    Write-Out "port $QueryPort $how" (($hist -join ',') + "`r`n" + $pl + "`r`nseen " + $seen)
    $left = 1000 - ([Environment]::TickCount - $t0)
    if ($left -gt 0) { Start-Sleep -Milliseconds $left }
}
