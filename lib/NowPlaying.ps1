# ArkSense - lib\NowPlaying.ps1
# Tells ArkSense which song / video is playing, for the "Now playing" overlay.
#
# Reads Windows' own media sessions (the same list the volume flyout and the lock
# screen show: GlobalSystemMediaTransportControlsSessionManager). Chrome, Edge,
# Firefox, Opera, Brave etc. publish YouTube / YouTube Music there with title,
# channel / artist, position and thumbnail. Nothing inside any browser is read and
# nothing is sent anywhere; this only asks Windows.
#
# Output file, rewritten every second (UTF-8, temp file + rename), "key<TAB>value":
#   state   ok | error <reason>
#   status  Playing | Paused | Stopped | none
#   app     the player's id (chrome, msedge, firefox, spotify ...)
#   title / artist / album
#   pos / len   seconds (pos already moved on to "now" while playing)
#   cover   path of the thumbnail file, or empty
# Exits by itself when ArkSense (-Parent) is gone.

param(
    [Parameter(Mandatory = $true)][string]$Out,
    [Parameter(Mandatory = $true)][int]$Parent,
    [int]$Any = 0
)

$ErrorActionPreference = 'Stop'
$tmp = "$Out.tmp"
$coverDir = Split-Path -Parent $Out

function Write-Out([string]$txt) {
    try {
        [System.IO.File]::WriteAllText($tmp, $txt, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $Out -Force
    } catch { }
}

function Alive { return [bool](Get-Process -Id $Parent -ErrorAction SilentlyContinue) }

function Clean([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace "[`t`r`n]", ' ').Trim()
}

try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $script:asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
    $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
} catch {
    Write-Out ("state`terror media sessions unavailable on this Windows (" + (Clean $_.Exception.Message) + ")")
    while (Alive) { Start-Sleep -Seconds 30 }
    exit 0
}

# wait for a WinRT async call, at most 3 s
function Await($op, [Type]$type) {
    $t = $script:asTask.MakeGenericMethod($type).Invoke($null, @($op))
    if (-not $t.Wait(3000)) { throw 'Windows did not answer in time' }
    return $t.Result
}

try {
    $mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) `
                 ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
} catch {
    Write-Out ("state`terror media sessions unavailable (" + (Clean $_.Exception.Message) + ")")
    while (Alive) { Start-Sleep -Seconds 30 }
    exit 0
}

$browsers = '(?i)chrome|msedge|edge|firefox|308046B0AF4A39CB|opera|brave|vivaldi|yandex|arc|floorp|librewolf|waterfox'
$lastKey = ''
$cover = ''
$coverN = 0
$keepApp = ''

while (Alive) {
    $t0 = [Environment]::TickCount
    $txt = "state`tok`nstatus`tnone"
    try {
        $pick = $null
        $paused = $null
        foreach ($s in $mgr.GetSessions()) {
            $app = [string]$s.SourceAppUserModelId
            if ($Any -eq 0 -and $app -notmatch $browsers) { continue }
            $st = [string]$s.GetPlaybackInfo().PlaybackStatus
            if ($st -eq 'Playing') { if (-not $pick -or $app -eq $keepApp) { $pick = $s } }
            elseif (-not $paused -or $app -eq $keepApp) { $paused = $s }
        }
        if (-not $pick) { $pick = $paused }
        if ($pick) {
            $keepApp = [string]$pick.SourceAppUserModelId
            $p = Await ($pick.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
            $st = [string]$pick.GetPlaybackInfo().PlaybackStatus
            $tl = $pick.GetTimelineProperties()
            $pos = -1; $len = -1
            try {
                $len = [double]$tl.EndTime.TotalSeconds
                $pos = [double]$tl.Position.TotalSeconds
                if ($st -eq 'Playing' -and $tl.LastUpdatedTime.Year -gt 2000) {
                    $pos += ([DateTimeOffset]::Now - $tl.LastUpdatedTime).TotalSeconds
                }
                if ($len -gt 0 -and $pos -gt $len) { $pos = $len }
            } catch { }
            $title = Clean $p.Title
            $artist = Clean $p.Artist
            $key = $keepApp + '|' + $title + '|' + $artist
            if ($key -ne $lastKey) {
                $lastKey = $key
                # new song: save its thumbnail to a fresh file (the old one may be open in ArkSense)
                $old = $cover
                $cover = ''
                try {
                    if ($p.Thumbnail) {
                        $ras = Await ($p.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
                        $src = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($ras)
                        $coverN++
                        $path = Join-Path $coverDir ("ArkSense-cover-" + $coverN + ".img")
                        $fs = [System.IO.File]::Create($path)
                        try { $src.CopyTo($fs) } finally { $fs.Close(); $src.Dispose() }
                        if ((Get-Item -LiteralPath $path).Length -gt 0) { $cover = $path }
                    }
                } catch { }
                # tidy older thumbnails (skips the ones still in use)
                Get-ChildItem -LiteralPath $coverDir -Filter 'ArkSense-cover-*.img' -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -ne $cover -and $_.FullName -ne $old } |
                    ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force } catch { } }
            }
            $inv = [Globalization.CultureInfo]::InvariantCulture
            $txt = "state`tok`nstatus`t$st`napp`t" + (Clean $keepApp) + "`ntitle`t$title`nartist`t$artist" +
                   "`nalbum`t" + (Clean $p.AlbumTitle) + "`npos`t" + $pos.ToString('0.0', $inv) +
                   "`nlen`t" + $len.ToString('0.0', $inv) + "`ncover`t$cover"
        } else {
            $lastKey = ''
        }
    } catch {
        $txt = "state`tok`nstatus`tnone`nnote`t" + (Clean $_.Exception.Message)
    }
    Write-Out $txt
    $left = 1000 - ([Environment]::TickCount - $t0)
    if ($left -gt 0) { Start-Sleep -Milliseconds $left }
}
Get-ChildItem -LiteralPath $coverDir -Filter 'ArkSense-cover-*.img' -ErrorAction SilentlyContinue |
    ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force } catch { } }
