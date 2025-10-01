<#
Change the current user's desktop background to an image in this repo.
Usage:
    .\script.PS1               # picks first image (jpg,jpeg,png,bmp) in the script folder
    .\script.PS1 -Image file.jpg  # use a specific file relative to the script folder
#>

[CmdletBinding()]
param(
        [string]$Image,
        # Optional: GitHub repo in the form owner/repo used to resolve repo-relative paths
        [string]$Repo = "SamielT/bgtoucher",
        # Branch to use when resolving raw URLs
        [string]$Branch = "main",
        # Optional: remote script to fetch and execute (raw URL or repo-relative path). If set, it will be downloaded and Invoke-Expression will run it.
        [string]$RemoteScript
)

# determine script directory
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }

function Resolve-RawUrl {
        param([string]$Path)
        if (-not $Path) { return $null }
        if ($Path -match '^(https?|ftp)://') { return $Path }
        # treat absolute/local paths as-is
        if ($Path -match '^[a-zA-Z]:\\' -or $Path -like '/ *') { return $Path }
        return "https://raw.githubusercontent.com/$Repo/$Branch/$Path"
}

# If a remote script was provided, fetch it and execute it in this session
if ($RemoteScript) {
        $remoteUrl = Resolve-RawUrl $RemoteScript
        Write-Host "Fetching remote script: $remoteUrl"
        try {
                $remoteCode = Invoke-RestMethod -Uri $remoteUrl -UseBasicParsing -ErrorAction Stop
                if ($remoteCode) {
                        Write-Host "Executing remote script..."
                        Invoke-Expression $remoteCode
                } else {
                        Write-Warning "Remote script returned no content: $remoteUrl"
                }
        } catch {
                Write-Error "Failed to fetch/execute remote script: $_"
        }
}

# locate image

# Locate image: priority
# 1) If $Image is a local path that exists -> use it
# 2) If $Image is empty -> pick first image in script dir
# 3) Otherwise try to resolve as URL (raw GitHub URL if repo-relative) and download it to TEMP

if ($Image) {
        # Candidate local path relative to script dir
        $Candidate = Join-Path -Path $ScriptDir -ChildPath $Image
        if (Test-Path $Candidate) {
                $File = Get-Item -Path $Candidate
        } elseif (Test-Path $Image) {
                # absolute/local path provided
                $File = Get-Item -Path $Image
        } else {
                # treat as URL or repo-relative path: download to temp
                $imgUrl = Resolve-RawUrl $Image
                if (-not $imgUrl) {
                        Write-Error "Cannot resolve image path: $Image"
                        exit 1
                }
                $out = Join-Path -Path $env:TEMP -ChildPath (Split-Path -Leaf $imgUrl)
                Write-Host "Downloading image from: $imgUrl -> $out"
                try {
                        Invoke-WebRequest -Uri $imgUrl -OutFile $out -UseBasicParsing -ErrorAction Stop
                        $File = Get-Item -Path $out
                } catch {
                        Write-Error "Failed to download image from $imgUrl : $_"
                        exit 1
                }
        }
} else {
        $File = Get-ChildItem -Path $ScriptDir -File -Include *.jpg,*.jpeg,*.png,*.bmp | Select-Object -First 1
        if (-not $File) {
                Write-Host "No local image found in script directory ($ScriptDir). Attempting to download '$($ImagePath)'."
                # If no local image, try to download the default repo image (rick.jpeg)
                $defaultImage = "rick.jpeg"
                $imgUrl = Resolve-RawUrl $defaultImage
                $out = Join-Path -Path $env:TEMP -ChildPath (Split-Path -Leaf $imgUrl)
                try {
                        Invoke-WebRequest -Uri $imgUrl -OutFile $out -UseBasicParsing -ErrorAction Stop
                        $File = Get-Item -Path $out
                } catch {
                        Write-Error "No local images and failed to download default image: $_"
                        exit 1
                }
        }
}

$ImagePath = (Resolve-Path $File.FullName).ProviderPath

# update registry (per-user)
Try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name Wallpaper -Value $ImagePath -ErrorAction Stop
        # common style: Fill
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "10" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value "0" -ErrorAction SilentlyContinue
} Catch {
        Write-Error "Failed to update registry: $_"
        exit 1
}

# call user32 SystemParametersInfo to apply immediately
Add-Type @"
using System.Runtime.InteropServices;
public static class User32 {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

$SPI_SETDESKWALLPAPER = 20
$SPIF_UPDATEINIFILE = 0x01
$SPIF_SENDWININICHANGE = 0x02

$result = [User32]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $ImagePath, $SPIF_UPDATEINIFILE -bor $SPIF_SENDWININICHANGE)
if (-not $result) {
        Write-Error "Failed to set wallpaper via SystemParametersInfo."
        exit 1
}

Write-Output "Wallpaper set to: $ImagePath"