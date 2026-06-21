# Script written by @lesongvi for HG Logistics navigation voice mod
# Website: https://truckers.vn
# This script will download the latest version of ts-fmod-plugin.dll and copy it to the ETS2 and ATS game directories.

$ErrorActionPreference = "Stop"

$ConfigFile = Join-Path $PSScriptRoot "..\configs\conf.ini"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Error: Configuration file missing at $ConfigFile"
    Exit 1
}

function Get-IniValue($key) {
    $line = Select-String -Path $ConfigFile -Pattern "^\s*$key\s*="
    if ($line) {
        return ($line.Line -split '=')[1].Trim().Trim('"').Trim("'")
    }
    return $null
}

function Set-IniValue($key, $value) {
    $content = Get-Content $ConfigFile
    $escapedValue = $value -replace '\\', '\\'
    if ($content -match "^\s*$key\s*=") {
        $content -replace "^\s*$key\s*=.*", "$key = `"$escapedValue`"" | Set-Content $ConfigFile
    } else {
        Add-Content -Path $ConfigFile -Value "$key = `"$escapedValue`""
    }
}

function Prompt-ForRootDirectory($GameName, $IniKey) {
    Add-Type -AssemblyName System.Windows.Forms
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderBrowser.Description = "Select the root installation folder for $GameName (the directory containing the 'bin' folder)"
    $FolderBrowser.ShowNewFolderButton = $false
    
    Write-Host "$GameName path not set or invalid. Opening folder picker..." -ForegroundColor Yellow
    
    $Process = Get-Process -Id $PID
    $Window = New-Object System.Windows.Forms.NativeWindow
    $Window.AssignHandle($Process.MainWindowHandle)
    
    $Result = $FolderBrowser.ShowDialog($Window)
    
    if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
        $SelectedPath = $FolderBrowser.SelectedPath
        Set-IniValue $IniKey $SelectedPath
        return $SelectedPath
    }
    return $null
}

$HostUrl  = Get-IniValue "host"
$Version  = Get-IniValue "version"
$Ets2Root = Get-IniValue "ets2_root"
$AtsRoot  = Get-IniValue "ats_root"
$RawVol   = Get-IniValue "volume"

$Volume = "{0:F2}" -f ([int]$RawVol / 100)

$FmodPluginUrl = "$HostUrl/plugins/ts-fmod-plugin/$Version/ts-fmod-plugin.dll"

function Install-Mod($GameName, $GameRoot, $GameCode) {
    $PluginDir = Join-Path $GameRoot "bin\win_x64\plugins"
    $TargetDir = Join-Path $PluginDir "ts-fmod-plugin"
    
    Write-Host "----------------------------------------"
    Write-Host "Installing HG Logistics navigation voice mod for $GameName..."
    
    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    }
    
    Invoke-WebRequest -Uri $FmodPluginUrl -OutFile (Join-Path $PluginDir "ts-fmod-plugin.dll") -UseBasicParsing
    
    Invoke-WebRequest -Uri "$HostUrl/plugins/ts-fmod-plugin/$Version/$GameCode/master.bank" -OutFile (Join-Path $TargetDir "master.bank") -UseBasicParsing
    Invoke-WebRequest -Uri "$HostUrl/plugins/ts-fmod-plugin/$Version/hg_navigation.bank" -OutFile (Join-Path $TargetDir "hg_navigation.bank") -UseBasicParsing
    Invoke-WebRequest -Uri "$HostUrl/plugins/ts-fmod-plugin/$Version/hg_navigation.bank.guids" -OutFile (Join-Path $TargetDir "hg_navigation.bank.guids") -UseBasicParsing

    $SelectedBankPath = Join-Path $TargetDir "selected.bank.txt"
    $SelectedBankContent = (Invoke-WebRequest -Uri "$HostUrl/plugins/ts-fmod-plugin/$Version/selected.bank.txt" -UseBasicParsing).Content
    $RemoteLines = $SelectedBankContent -split '\r?\n' | Where-Object { $_.Trim() -ne "" }

    if (Test-Path $SelectedBankPath) {
        $LocalLines = Get-Content $SelectedBankPath
        foreach ($Line in $RemoteLines) {
            if ($LocalLines -notcontains $Line) {
                Add-Content -Path $SelectedBankPath -Value $Line
            }
        }
    } else {
        Set-Content -Path $SelectedBankPath -Value $SelectedBankContent
    }
    
    $SoundLevelsPath = Join-Path $TargetDir "sound_levels.txt"
    $RegexPattern = '"navigation":\s*[0-9.]+'
    $ReplacePattern = "`"navigation`": $Volume"

    if (Test-Path $SoundLevelsPath) {
        $Content = Get-Content $SoundLevelsPath -Raw
        $Content -replace $RegexPattern, $ReplacePattern | Set-Content $SoundLevelsPath
    } else {
        $RemoteContent = (Invoke-WebRequest -Uri "$HostUrl/plugins/ts-fmod-plugin/$Version/sound_levels.txt" -UseBasicParsing).Content
        $RemoteContent -replace $RegexPattern, $ReplacePattern | Set-Content $SoundLevelsPath
    }
    
    Write-Host "$GameName installation complete." -ForegroundColor Green
}

if (-not $Ets2Root -or -not (Test-Path $Ets2Root)) {
    $Ets2Root = Prompt-ForRootDirectory "Euro Truck Simulator 2" "ets2_root"
}

if ($Ets2Root -and (Test-Path $Ets2Root)) {
    Install-Mod "Euro Truck Simulator 2" $Ets2Root "ETS2"
} else {
    Write-Host "ETS2 installation skipped." -ForegroundColor Cyan
}

if (-not $AtsRoot -or -not (Test-Path $AtsRoot)) {
    $AtsRoot = Prompt-ForRootDirectory "American Truck Simulator" "ats_root"
}

if ($AtsRoot -and (Test-Path $AtsRoot)) {
    Install-Mod "American Truck Simulator" $AtsRoot "ATS"
} else {
    Write-Host "ATS installation skipped." -ForegroundColor Cyan
}