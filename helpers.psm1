# helpers.psm1
# Shared utilities for Chocolatey package update scripts.
# Lives at repo root. Import with: Import-Module "$PSScriptRoot\helpers.psm1" -Force

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    $Timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$Timestamp] $Message" -ForegroundColor $Color
}

function Get-GeckoDriver {
    <#
    .SYNOPSIS
        Locates geckodriver.exe on the system, or downloads the latest win64 release from GitHub.
    .OUTPUTS
        The directory path containing geckodriver.exe.
    #>
    $FoundCmd = Get-Command geckodriver.exe -ErrorAction SilentlyContinue
    $PossiblePaths = @(
        "C:\webdrivers",
        "C:\ProgramData\chocolatey\bin",
        "C:\ProgramData\chocolatey\lib\selenium-gecko-driver\tools",
        $PSScriptRoot,
        "$PSScriptRoot\tools"
    )

    if ($null -ne $FoundCmd) { $PossiblePaths += Split-Path $FoundCmd.Path }

    foreach ($Path in $PossiblePaths) {
        if ($null -ne $Path -and (Test-Path "$Path\geckodriver.exe")) {
            Write-Log "Found geckodriver at: $Path" -Color Gray
            return $Path
        }
    }

    Write-Log "geckodriver.exe not found. Downloading latest win64 release from GitHub..." -Color Cyan

    $Dest = Join-Path $PSScriptRoot "tools"
    if (-not (Test-Path $Dest)) { New-Item $Dest -ItemType Directory | Out-Null }

    $Release = Invoke-RestMethod "https://api.github.com/repos/mozilla/geckodriver/releases/latest" -UseBasicParsing
    $Asset   = $Release.assets | Where-Object { $_.name -match 'win64' -and $_.name -match 'zip' } | Select-Object -First 1

    if (-not $Asset) { throw "Could not find a win64 geckodriver asset in the latest GitHub release." }

    $ZipPath = Join-Path $Dest "gecko.zip"
    Invoke-WebRequest $Asset.browser_download_url -OutFile $ZipPath -UseBasicParsing
    Expand-Archive -Path $ZipPath -DestinationPath $Dest -Force
    Remove-Item $ZipPath -Force

    Write-Log "geckodriver downloaded to: $Dest" -Color Green
    return $Dest
}

function Test-UpdateNeeded {
    <#
    .SYNOPSIS
        Compares a remote version string against the version in the local .nuspec file.
        Returns $true if an update is needed, $false if versions match.
        PackageDir must be passed explicitly — typically $PSScriptRoot from the calling script.
    .NOTES
        AU already performs version comparison internally, but this short-circuits
        before expensive operations (Selenium scraping, hash fetching) when not needed.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RemoteVersion,

        [Parameter(Mandatory)]
        [string]$PackageDir
    )

    $Nuspec = Get-ChildItem "$PackageDir\*.nuspec" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $Nuspec) {
        Write-Log "No .nuspec found in $PackageDir — assuming update is needed." -Color Yellow
        return $true
    }

    [xml]$Xml = Get-Content $Nuspec.FullName
    $LocalVersion = $Xml.package.metadata.version

    if ($LocalVersion -eq $RemoteVersion) {
        Write-Log "Local version ($LocalVersion) matches remote ($RemoteVersion). Skipping." -Color Gray
        return $false
    }

    Write-Log "Update needed: $LocalVersion -> $RemoteVersion" -Color Cyan
    return $true
}

Export-ModuleMember -Function Write-Log, Get-GeckoDriver, Test-UpdateNeeded