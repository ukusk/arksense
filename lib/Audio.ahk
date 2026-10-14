; ArkSense - lib\Audio.ahk
; MP3 music and click sound through winmm MCI.
; Part of ArkSense.ahk; run that file, not this one.

; ---- Audio: MP3 music + click sound via winmm MCI --------------------------
Mci(cmd) {
    buf := Buffer(512, 0)            ; 256 WCHARs; the length below is in characters
    DllCall("winmm\mciSendStringW", "Str", cmd, "Ptr", buf, "UInt", 256, "Ptr", 0)
    return StrGet(buf)
}

MusicStart() {
    MusicStop()
    if (Trim(Audio.MusicPath) = "" || !FileExist(Audio.MusicPath))
        return
    Mci("Close ark_music")
    Mci('Open "' . Audio.MusicPath . '" Type MPEGVideo Alias ark_music')
    Mci("Play ark_music Repeat")
    Audio.MusicOpen := true
}

MusicStop() {
    if Audio.MusicOpen {
        Mci("Stop ark_music")
        Mci("Close ark_music")
        Audio.MusicOpen := false
    }
}

PlayClick() {
    if (!Audio.ClickOn || Trim(Audio.ClickPath) = "" || !FileExist(Audio.ClickPath))
        return
    ; short one-shot on its own alias so it can overlap the music device
    Mci("Close ark_click")
    Mci('Open "' . Audio.ClickPath . '" Type MPEGVideo Alias ark_click')
    Mci("Play ark_click From 0")
}

; start or stop the music loop to match the current Audio settings
SyncMusic() {
    if (Audio.MusicOn && Trim(Audio.MusicPath) != "")
        MusicStart()
    else
        MusicStop()
}
