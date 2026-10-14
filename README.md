# ArkSense

## NB! Puuduvad eelnevad commitid, kuna hoiustasin faile viimased 2-3 nädalat lokaalselt, repo on tehtud vaid töö esitamiseks.


## Nõuded

- Windows 10 või 11, 64-bitine. Voogedastusrežiim vajab Windows 10 versiooni 2004 või uuemat.
- [AutoHotkey v2.0](https://www.autohotkey.com/) (paigaldatud).
- Administraatoriõigused – käivitamisel tuleb UAC küsimusele vastata „Jah“.
- ARK: Survival Evolved (`ShooterGame.exe`) või ARK: Survival Ascended, ekraanirežiimiks **Borderless** (ääristeta aken).
- .NET Framework 4 ja Windows PowerShell 5.1 – mõlemad on Windowsis juba olemas. Neid on vaja sujuva ülekatte, FPS-loenduri, pingi, serveri tuvastuse ja „Praegu mängib“ jaoks.
- Microsoft Edge WebView2 Runtime veebimenüü jaoks. Kui see puudub, kasutatakse tavalist (Native) menüüd.
- Kogu ArkSense'i kaust koos `lib`-kaustaga peab olema koos.
- Internetiühendus pingi ja serveripäringu jaoks.
- Antidoodi jaoks tuleb määrata skaneerimisala praeguse ekraani eraldusvõime jaoks (vaheleht **Antidoot**).

## Käivitamine

1. Laadi alla kogu kaust (koos `lib`-kaustaga).
2. Käivita `ArkSense.ahk` ja vasta UAC küsimusele „Jah“.
3. Ava ja sulge menüü **Insert**-klahviga.

## Mis on ArkSense?

ArkSense on AutoHotkey v2 abiprogramm mängule ARK: Survival Evolved (töötab ka ARK: Survival Ascendediga). See vajutab klahve ja hiirenuppe sinu eest, loeb ainult sinu enda ekraani piksleid ning näitab mängu peal ülekatteid (statistika, olekud, muusika, clantag). Programm ei loe mängu mälu ega muuda mängu faile.

Menüü avaneb ja sulgub Insert-klahviga. Seaded salvestatakse faili `ArkSense.ini` programmi kausta.

## Funktsioonid

### Peamine

- **Antidoot** – vajutab antidoodi hotbar-klahvi, kui buffi ikooni ekraanil pole, kontrollib, kas see õnnestus, ja proovib vajadusel uuesti. Loendur „ok / fail“ näitab õnnestunud ja ebaõnnestunud vajutusi.
- **Makrod** – Remount (lisa E-vajutus), Insta-Bag (klõps salvestatud kohas), mammuti klikker koos rütmimõõtjaga ja autoklikker (1–60 klõpsu sekundis, ajastuse juhuslik varieerumine).
- **OC makro** – hoiab Shifti all ja vajutab klahve 1, 2, 3 järjest.
- **Mäng** – konsooli eelseaded (FPS-käsud), ekraani värvifiltrid (ka värvipimeduse abi) ja teavitused (antidoot ebaõnnestus, serveri viivitus, ühenduse kadu).

### Visuaalid

- **Ülekate** – olekupillid; statistikakaart (CPU, RAM, GPU, kell, pingi graafik, jitter, kadu, FPS, mängijate arv); serveri automaatne tuvastus; 3 salvestatavat paigutust kiirklahvidega; voogedastusrežiim, mis peidab menüü ja ülekatted salvestustest.
- **Praegu mängib** – väike kaart YouTube'i või muusikarakenduse loo nime, pildi ja edenemisribaga.
- **Clantag & riba** – animeeritud silt (Build-up või Decode) eraldi kastis või statistikakaardil. Statistikakaardi saab näidata õhukese ribana: logo, ArkSense, ping, FPS ning soovi korral CPU, GPU, RAM ja silt. Valida saab 8 logo vahel.
- **Välimus** – menüü taustad (Aurora, Embers, Frosted glass, Holo), neoonservad, prožektor, värvikorrektsioon, teemad, efektid ja käivitusanimatsioon.

### Süsteem

- **Seaded** – värvid, menüü tüüp (Web või Native), font, taustapilt, heli, logo, sinu nimi ja profiilid.
- **Häälestus** – Windowsi mängurežiim, Game Bari salvestus, HAGS, toiteplaan ja ARK-i protsessi prioriteet. Kõik muudatused saab tagasi võtta.
- **Logid** – ArkSense'i enda tegevuste logi, enesekontroll ja hädaseiskamisklahv, mis peatab kõik makrod ja sulgeb programmi.
- **Muu** – puhas ekraanipilt ilma ülekateteta ja seadete otsing (Ctrl+F).
