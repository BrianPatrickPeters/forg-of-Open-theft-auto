Write-Host "Brian-Patch wird vorbereitet..."
$ErrorActionPreference = "Stop"

$human = Join-Path $PSScriptRoot "scripts\human.gd"
$game  = Join-Path $PSScriptRoot "scripts\game.gd"

if (!(Test-Path $human) -or !(Test-Path $game)) {
    throw "Projektdateien nicht gefunden. Bitte nichts aendern."
}

$h = Get-Content $human -Raw
$g = Get-Content $game -Raw

if ($h.Contains('"brian": {') -or $h.Contains('BRIAN_SCENE')) {
    throw "Brian scheint bereits eingetragen zu sein. Keine Aenderung vorgenommen."
}

$preload = 'const PETER_SCENE: PackedScene = preload("res://assets/characters/peter/scene.gltf")'
if (!$h.Contains($preload)) {
    throw "Peter-Preload nicht gefunden. Keine Aenderung vorgenommen."
}

$h = $h.Replace(
    $preload,
    $preload + "`r`nconst BRIAN_SCENE: PackedScene = preload(""res://assets/characters/Brian/Basic Shooter Pack/FERTIGES BRIANmodell.fbx"")"
)

$pattern = '(?m)^}(?=\r?\n\r?\n## Civilians pick from this list so the street shows)'
if ([regex]::Matches($h, $pattern).Count -ne 1) {
    throw "Einfuegestelle nicht eindeutig. Keine Dateien geschrieben."
}

$brian = @'
        "brian": {
                "scene": BRIAN_SCENE, "height_scale": 1.93, "face_offset": 0.0, "clothed": true,
                "bones": {
                        "thigh_l": "leftupleg", "thigh_r": "rightupleg",
                        "upperarm_l": "leftarm", "upperarm_r": "rightarm", "hand_r": "righthand",
                },
        },
'@

$h = [regex]::Replace($h, $pattern, $brian + "`r`n}", 1)

$joint = '"peter": ["calf_l", "calf_r", "lowerarm_l", "lowerarm_r"],'
if (!$h.Contains($joint)) {
    throw "Gelenkzuordnung nicht gefunden. Keine Dateien geschrieben."
}
$h = $h.Replace($joint, $joint + "`r`n        ""brian"": [""leftleg"", ""rightleg"", ""leftforearm"", ""rightforearm""],")

$oldPlayer = 'player_node = Human.build_model("peter")'
if (!$g.Contains($oldPlayer)) {
    throw "Spieler-Zeile nicht gefunden. Keine Dateien geschrieben."
}
$g = $g.Replace($oldPlayer, 'player_node = Human.build_model("brian")')

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
Copy-Item $human "$human.before_brian_$stamp.bak"
Copy-Item $game "$game.before_brian_$stamp.bak"

Set-Content -LiteralPath $human -Value $h -Encoding utf8
Set-Content -LiteralPath $game -Value $g -Encoding utf8

Write-Host "Brian wurde eingetragen. Pete-Sicherungen bleiben erhalten."


