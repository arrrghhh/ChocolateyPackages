# ==============================
#   update.ps1 — FileZilla AU
# ==============================

function Ensure-Module {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [string] $MinVersion
    )

    # Already imported?
    if (Get-Module -Name $Name -ListAvailable -ErrorAction SilentlyContinue) {
        try {
            Import-Module $Name -ErrorAction Stop
            Write-Host "Module '$Name' imported successfully."
            return
        } catch {
            Write-Warning "Module '$Name' exists but could not be loaded: $_"
        }
    }

    Write-Warning "Module '$Name' not found. Attempting installation..."

    # Try PowerShell Gallery install
    try {
        Install-Module $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Import-Module $Name -ErrorAction Stop
        Write-Host "Module '$Name' installed and imported successfully."
        return
    }
    catch {
        Write-Warning "Could not install module '$Name' from PSGallery: $_"
    }

    throw "FATAL: Module '$Name' is missing and could not be installed."
}

Ensure-Module -Name 'Chocolatey-AU'
Ensure-Module -Name 'Selenium'

$PackageId   = "filezilla"
$ReleasePage = "https://filezilla-project.org/download.php?show_all=1"
$ToolsDir    = "$PSScriptRoot\tools"

# ------------------------------------------------------------
# Step 0 — Helper: Check if update is needed
# ------------------------------------------------------------

function Test-UpdateNeeded {
    param($LatestVersion)

    Write-Host "Checking Chocolatey for existing/pending versions..."

    # Get all known versions from Chocolatey API
    $ApiUrl = "https://community.chocolatey.org/api/v2/Packages()?"
    $ApiUrl += "`$filter=(Id eq '$PackageId')&includePrerelease=true"

    $AvailablePackages = Invoke-RestMethod $ApiUrl

    # Skip if exact version exists
    if ($LatestVersion -in $AvailablePackages.properties.version) {
        Write-Host "$PackageId $LatestVersion already published → skipping update."
        return $false
    }

    # Check if version is submitted but not approved
    try {
        $SpecificUrl = "https://community.chocolatey.org/api/v2/Packages(Id='$PackageId',Version='$LatestVersion')"
        $SpecificResult = Invoke-RestMethod $SpecificUrl

        if ($SpecificResult.entry.properties.PackageStatus -ne 'Approved') {
            Write-Host "$PackageId $LatestVersion is pending approval → skipping update."
            return $false
        }
    } catch {
        # Not found → OK to continue
    }

    return $true
}

# ------------------------------------------------------------
# Step 1 — Get Latest Version and URLs via Selenium
# ------------------------------------------------------------
function global:au_GetLatest {
    Write-Host "Starting Selenium to extract latest FileZilla URLs..."

    $Driver = Start-SeDriver `
        -Browser "firefox" `
        -State Headless `
        -StartURL $ReleasePage `
        -DefaultDownloadPath $ToolsDir

    $Elem32 = Get-SeElement -By PartialLinkText "_win32-setup.exe"
    $Elem64 = Get-SeElement -By PartialLinkText "_win64-setup.exe"

    $URL32 = $Elem32.GetAttribute("href")
    $URL64 = $Elem64.GetAttribute("href")

    # Parse version from URL
    $Version = ([uri]$URL32).Segments[-1].Split('_')[-2]

    if (-not ($Version -as [version])) {
        throw "Could not parse version from download URL: $URL32"
    }

    Write-Host "Found latest version: $Version"

    $Driver.Quit()
    $Driver.Dispose()

    return @{
        Version  = $Version
        FileType = "exe"
    }
}

# ------------------------------------------------------------
# Step 2 — Download the installers via Selenium
# Also performs version check here
# ------------------------------------------------------------
function global:au_BeforeUpdate {
    <#
    # Skip update if version exists or pending approval
    if (-not (Test-UpdateNeeded $Latest.Version)) {
        Write-Host "Update skipped."
        return
    }
    #>
    $Version = $Latest.Version
    Write-Host "Downloading FileZilla installers using Selenium..."

    # Clean old files
    Remove-Item "$ToolsDir\FileZilla_3*.exe" -Force -ErrorAction SilentlyContinue

    $Driver = Start-SeDriver `
        -Browser "firefox" `
        -State Headless `
        -StartURL $ReleasePage `
        -DefaultDownloadPath $ToolsDir

    # Trigger real downloads (JS click)
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
}

# ------------------------------------------------------------
# Step 3 — Update scripts and verification file
# ------------------------------------------------------------
function global:au_SearchReplace {
    @{
        ".\tools\chocolateyInstall.ps1" = @{
            "(?i)(^\s*packageName\s*=\s*)('.*')" = "`$1'$($Latest.PackageName)'"
        }

        ".\legal\VERIFICATION.txt" = @{
            "(?i)(\s+x32:).*"     = "`${1} $($Latest.URL32)"
            "(?i)(\s+x64:).*"     = "`${1} $($Latest.URL64)"
            "(?i)(checksum32:).*" = "`${1} $($Latest.Checksum32)"
            "(?i)(checksum64:).*" = "`${1} $($Latest.Checksum64)"
        }
    }
}

# ------------------------------------------------------------
# Step 4 — Run AU update
# ------------------------------------------------------------
update -ChecksumFor none -NoCheckUrl
