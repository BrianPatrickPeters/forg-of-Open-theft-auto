param(
    [string]$ProjectPath = "C:\Users\teequ\Desktop\Projekte\Godot_v4.7.2-stable_win64.exe\Projects\folder\open-theft-auto-main\open-theft-auto-main"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
    Write-Host "Projektordner nicht gefunden: $ProjectPath" -ForegroundColor Red
    exit 1
}

$logPath = Join-Path $ProjectPath "PROJEKT_AKTIVITAET.log"
$statusPath = Join-Path $ProjectPath "PROJEKT_STATUS_AUTO.txt"

function Write-Log([string]$Message) {
    $line = "{0} | {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Write-Status {
    $lines = @(
        "OPEN THEFT AUTO - AUTOMATISCHER STATUS",
        "Aktualisiert: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Projektordner: $ProjectPath",
        "",
        "Ziel: grafischer 3D-Stadteditor; MMB-Kamerabewegung; Rechtsklick-Kontextmenue;",
        "Objekte platzieren/auswaehlen/verschieben/drehen/skalieren/loeschen; Speichern/Laden.",
        "Spaeter: vorhandene Welt/Assets integrieren und zufaellige, erweiterbare Stadt untersuchen.",
        "",
        "Wichtige Dateien:"
    )
    $editorScript = Join-Path $ProjectPath "scripts\editor\city_editor.gd"
    $projectFile = Join-Path $ProjectPath "project.godot"
    foreach ($file in @($projectFile, $editorScript)) {
        if (Test-Path -LiteralPath $file) {
            $item = Get-Item -LiteralPath $file
            $lines += ("- {0} | geaendert: {1} | Bytes: {2}" -f $item.FullName, $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), $item.Length)
        } else {
            $lines += ("- FEHLT: {0}" -f $file)
        }
    }
    $lines += @(
        "",
        "Letzte Logeintraege:",
        "Siehe PROJEKT_AKTIVITAET.log (diese Datei wird laufend ergaenzt).",
        "",
        "Hinweis: Dieses Skript protokolliert Dateisystem-Aenderungen waehrend es laeuft.",
        "Es kann ChatGPT-Chats nicht mitlesen und erkennt nicht automatisch, ob ein Codefehler behoben ist."
    )
    Set-Content -LiteralPath $statusPath -Value $lines -Encoding UTF8
}

Write-Log "LOGGER GESTARTET | $ProjectPath"
Write-Status

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $ProjectPath
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size, DirectoryName'
$watcher.InternalBufferSize = 32768
$watcher.EnableRaisingEvents = $true

$ignored = '\\(\.godot|\.git|\.import|output|cache|temp|tmp)\\'
$action = {
    $full = $Event.SourceEventArgs.FullPath
    if ($full -match $using:ignored) { return }
    $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
    $name = [IO.Path]::GetFileName($full)
    if ($ext -notin @('.gd','.tscn','.tres','.res','.godot','.json','.ps1','.bat','.cfg','.txt','.md','.gltf','.glb','.obj','.mtl') -and $name -notin @('project.godot')) { return }
    $change = $Event.SourceEventArgs.ChangeType
    $line = "{0} | DATEI {1} | {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $change, $full
    Add-Content -LiteralPath $using:logPath -Value $line -Encoding UTF8
    if ($full -like '*\scripts\editor\city_editor.gd' -or $name -eq 'project.godot') {
        $s = @(
            "OPEN THEFT AUTO - AUTOMATISCHER STATUS",
            "Aktualisiert: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "Projektordner: $using:ProjectPath",
            "",
            "Ziel: grafischer 3D-Stadteditor; MMB-Kamerabewegung; Rechtsklick-Kontextmenue;",
            "Objekte bearbeiten; Speichern/Laden; spaeter prozedural erweiterbare Stadt.",
            "",
            "Zuletzt geaenderte Datei: $full",
            "Ereignis: $change",
            "",
            "WICHTIG: Dateiaenderung bedeutet nicht automatisch, dass Godot-Syntaxpruefung erfolgreich war.",
            "Chat-Inhalte werden nicht automatisch erfasst."
        )
        Set-Content -LiteralPath $using:statusPath -Value $s -Encoding UTF8
    }
}
$subscriptions = @()
foreach ($eventName in @("Created","Changed","Deleted","Renamed")) {
    $subscriptions += Register-ObjectEvent -InputObject $watcher -EventName $eventName -SourceIdentifier "OTA_$eventName" -Action $action
}

Write-Host ""
Write-Host "Projekt-Logger laeuft. Fenster offen lassen." -ForegroundColor Green
Write-Host "Log:    $logPath"
Write-Host "Status: $statusPath"
Write-Host "Beenden mit STRG+C."
try {
    while ($true) { Wait-Event -Timeout 2 | Out-Null; Get-Event | Remove-Event -ErrorAction SilentlyContinue }
}
finally {
    $watcher.EnableRaisingEvents = $false
    foreach ($eventName in @("Created","Changed","Deleted","Renamed")) {
        Unregister-Event -SourceIdentifier "OTA_$eventName" -ErrorAction SilentlyContinue
    }
    $watcher.Dispose()
    Write-Log "LOGGER BEENDET"
}
