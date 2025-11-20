# ==============================
# update.ps1 — FileZilla standalone updater
# ==============================

param(
    [string]$PackageId = "filezilla",
    [string]$ReleasePage = "https://filezilla-project.org/download.php?show_all=1",
    [string]$ToolsDir = "$PSScriptRoot\tools"
)

Import-Module Selenium

# ------------------------------------------------------------
# Step 0 — Ensure tools folder exists
# ------------------------------------------------------------
if (-not (Test-Path $ToolsDir)) {
    New-Item -Path $ToolsDir -ItemType Directory | Out-Null
}

# ------------------------------------------------------------
# Step 1 — Launch Selenium and get latest URLs
# ------------------------------------------------------------
Write-Host "Starting Selenium to extract latest FileZilla URLs..."

$Driver = Start-SeDriver -Browser "firefox" -State Headless -StartURL $ReleasePage -DefaultDownloadPath $ToolsDir

$Elem32 = Get-SeElement -By PartialLinkText "_win32-setup.exe"
$Elem64 = Get-SeElement -By PartialLinkText "_win64-setup.exe"

$Url32 = $Elem32.GetAttribute("href")
$Url64 = $Elem64.GetAttribute("href")

# Parse version from URL
$Version = ([uri]$Url32).Segments[-1].Split('_')[-2]

if (-not ($Version -as [version])) {
    throw "Could not parse version from download URL: $Url32"
}

Write-Host "Latest version: $Version"

$Driver.Quit()
$Driver.Dispose()

# ------------------------------------------------------------
# Step 2 — Check if version already exists in Chocolatey
# ------------------------------------------------------------
$ApiUrl = "https://community.chocolatey.org/api/v2/Packages()?"
$ApiUrl += "`$filter=(Id eq '$PackageId')&includePrerelease=true"

$AvailablePackages = Invoke-RestMethod $ApiUrl

if ($Version -in $AvailablePackages.properties.version) {
    Write-Host "$PackageId $Version already published → skipping update."
    exit 0
}
<#
try {
    $SpecificUrl = "https://community.chocolatey.org/api/v2/Packages(Id='$PackageId',Version='$Version')"
    $SpecificResult = Invoke-RestMethod $SpecificUrl
    if ($SpecificResult.entry.properties.PackageStatus -ne 'Approved') {
        Write-Host "$PackageId $Version is pending approval → skipping update."
        exit 0
    }
} catch { }
#>
# ------------------------------------------------------------
# Step 3 — Download installers via Selenium
# ------------------------------------------------------------
Write-Host "Downloading FileZilla installers..."

# Clean old files
Remove-Item "$ToolsDir\FileZilla_*.exe" -Force -ErrorAction SilentlyContinue

$Driver = Start-SeDriver -Browser "firefox" -State Headless -StartURL $ReleasePage -DefaultDownloadPath $ToolsDir

(Get-SeElement -By PartialLinkText "_win32-setup.exe").Click()
(Get-SeElement -By PartialLinkText "_win64-setup.exe").Click()

# Wait for downloads to finish
$Local32 = "$ToolsDir\FileZilla_${Version}_win32-setup.exe"
$Local64 = "$ToolsDir\FileZilla_${Version}_win64-setup.exe"

$timeout = 120  # maximum wait in seconds
$interval = 2   # check every x seconds
$elapsed = 0

while (-not (Test-Path $Local32 -PathType Leaf -ErrorAction SilentlyContinue) -or
       -not (Test-Path $Local64 -PathType Leaf -ErrorAction SilentlyContinue)) {

    Start-Sleep -Seconds $interval
    $elapsed += $interval
    if ($elapsed -ge $timeout) {
        throw "Timeout waiting for FileZilla installers to download."
    }
}

Write-Host "Both installers are present."

$Driver.Quit()
$Driver.Dispose()

# Rename files to standard names
$Local32 = "$ToolsDir\FileZilla_${Version}_win32-setup.exe"
$Local64 = "$ToolsDir\FileZilla_${Version}_win64-setup.exe"

Get-ChildItem $ToolsDir -Filter "*win32-setup*.exe" | Rename-Item -NewName "FileZilla_${Version}_win32-setup.exe"
Get-ChildItem $ToolsDir -Filter "*win64-setup*.exe" | Rename-Item -NewName "FileZilla_${Version}_win64-setup.exe"

Write-Host "Downloads complete."

# ------------------------------------------------------------
# Step 4 — Compute SHA512 checksums
# ------------------------------------------------------------
$Checksum32 = (Get-FileHash -Algorithm SHA256 -Path $Local32).Hash
$Checksum64 = (Get-FileHash -Algorithm SHA265 -Path $Local64).Hash

Write-Host "Checksum (32-bit): $Checksum32"
Write-Host "Checksum (64-bit): $Checksum64"

# ------------------------------------------------------------
# Step 5 — Update VERIFICATION.txt
# ------------------------------------------------------------
$VerificationFile = "$PSScriptRoot\legal\VERIFICATION.txt"
$Content = Get-Content $VerificationFile

$Content = $Content -replace "(checksum32:).*", "`(checksum32:) $Checksum32"
$Content = $Content -replace "(checksum64:).*", "`(checksum64:) $Checksum64"

$Content | Set-Content $VerificationFile

Write-Host "VERIFICATION.txt updated."

# ------------------------------------------------------------
# Step 6 — Update .nuspec file
# ------------------------------------------------------------
$NuspecFile = "$PSScriptRoot\$PackageId.nuspec"
$NuspecContent = Get-Content $NuspecFile -Raw

# Replace the <version> element
$NuspecContent = $NuspecContent -replace "(?<=<version>).*?(?=</version>)", $Version

$NuspecContent | Set-Content $NuspecFile

Write-Host ".nuspec file updated to version $Version."

# ------------------------------------------------------------
# Step 7 — Pack nuspec
# ------------------------------------------------------------
choco pack $NuspecFile --version $Version

Write-Host "Update complete for FileZilla $Version."

