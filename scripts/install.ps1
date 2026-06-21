# Script written by @lesongvi for HG Logistics navigation voice mod
# Website: https://truckers.vn
# This script will download the latest version of ts-fmod-plugin.dll and copy it to the ETS2 and ATS game directories.

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ConfigFile = Join-Path $PSScriptRoot "..\configs\conf.ini"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Lỗi: Tệp cấu hình bị thiếu tại $ConfigFile"
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

function Get-GameVersion($GameRoot, $GameCode) {
    $ExeName = if ($GameCode -eq "ETS2") { "eurotrucks2.exe" } else { "amtrucks.exe" }
    $ExePath = Join-Path $GameRoot "bin\win_x64\$ExeName"
    
    if (Test-Path $ExePath) {
        $FullVersion = (Get-ItemProperty -Path $ExePath).VersionInfo.FileVersion.Trim()
        
        $VersionParts = $FullVersion.Split('.')
        return "$($VersionParts[0]).$($VersionParts[1])"
    }
    return "Unknown"
}

function Prompt-ForRootDirectory($GameName, $IniKey) {
    Add-Type -AssemblyName System.Windows.Forms
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderBrowser.Description = "Chọn thư mục cài đặt gốc cho $GameName (thư mục chứa 'bin')"
    $FolderBrowser.ShowNewFolderButton = $false
    
    Write-Host "Đường dẫn $GameName chưa được thiết lập hoặc không hợp lệ. Mở hộp thoại chọn thư mục..." -ForegroundColor Yellow
    
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

    $LocalGameVer = Get-GameVersion $GameRoot $GameCode

    Write-Host "----------------------------------------"
    Write-Host "Kiểm tra khả năng tương thích cho $GameName..."
    Write-Host "Phiên bản game: $LocalGameVer" -ForegroundColor Cyan

    $RemoteVersionUrl = "$HostUrl/plugins/ts-fmod-plugin/$Version/$GameCode/version.txt"

    try {
        Write-Host "Đang lấy thông tin khả năng tương thích của plugin từ server..."
        $JsonResponse = (Invoke-WebRequest -Uri $RemoteVersionUrl -UseBasicParsing -TimeoutSec 5).Content
        
        $RemoteData = ConvertFrom-Json $JsonResponse
        $TargetGameVer = $RemoteData.version
        
        Write-Host "Phiên bản plugin trên server: $TargetGameVer" -ForegroundColor Cyan
    } catch {
        Write-Host "Cảnh báo: Không thể xác minh phiên bản với server. Tiếp tục cài đặt..." -ForegroundColor Yellow
        $TargetGameVer = $LocalGameVer
    }

    if ($LocalGameVer -ne $TargetGameVer) {
        Write-Host "Cảnh báo: Phiên bản không khớp! Game của bạn là $LocalGameVer nhưng plugin được xây dựng cho $TargetGameVer." -ForegroundColor Yellow
        Write-Host "Mod có thể không hoạt động đúng." -ForegroundColor Yellow

        $Continue = Read-Host "Bạn có muốn tiếp tục cài đặt không? (Y/N)"
        if ($Continue -match "^[Nn]" -or [string]::IsNullOrEmpty($Continue)) {
            Write-Host "Cài đặt đã bị hủy bởi người dùng." -ForegroundColor Red
            return
        }
    } else {
        Write-Host "Kiểm tra phiên bản thành công. Game và plugin khớp hoàn hảo." -ForegroundColor Green
    }
    
    Write-Host "----------------------------------------"
    Write-Host "Đang cài đặt HG Logistics navigation voice mod cho $GameName..."
    
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

    foreach ($Line in $RemoteLines) {
        $CleanLine = $Line.Trim()
        if ($LocalLines.Trim() -notcontains $CleanLine) {
            Add-Content -Path $SelectedBankPath -Value $CleanLine
        }
    }

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
    
    Write-Host "Cài đặt mod cho $GameName hoàn tất." -ForegroundColor Green
}

if (-not $Ets2Root -or -not (Test-Path $Ets2Root)) {
    $Ets2Root = Prompt-ForRootDirectory "Euro Truck Simulator 2" "ets2_root"
}

if ($Ets2Root -and (Test-Path $Ets2Root)) {
    Install-Mod "Euro Truck Simulator 2" $Ets2Root "ETS2"
} else {
    Write-Host "Bỏ qua cài đặt ETS2." -ForegroundColor Cyan
}

if (-not $AtsRoot -or -not (Test-Path $AtsRoot)) {
    $AtsRoot = Prompt-ForRootDirectory "American Truck Simulator" "ats_root"
}

if ($AtsRoot -and (Test-Path $AtsRoot)) {
    Install-Mod "American Truck Simulator" $AtsRoot "ATS"
} else {
    Write-Host "Bỏ qua cài đặt ATS." -ForegroundColor Cyan
}