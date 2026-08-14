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

function Get-ChromeDriver {
    <#
    .SYNOPSIS
        Locates a chromedriver.exe compatible with the installed Chrome.
        If only a mismatched driver is present (Chrome/ChromeDriver drift),
        downloads the exact-matching driver from chrome-for-testing.
    .PARAMETER ChromeVersion
        The installed Chrome version (e.g. 151.0.7922.72). When provided, the
        driver's major version must match Chrome's major version.
    .OUTPUTS
        The directory path containing a compatible chromedriver.exe.
    #>
    param(
        [string]$ChromeVersion
    )

    $DesiredMajor = if ($ChromeVersion) { ($ChromeVersion -split '\.')[0] } else { $null }

    $FoundCmd = Get-Command chromedriver.exe -ErrorAction SilentlyContinue
    $PossiblePaths = @(
        "C:\webdrivers",
        "C:\ProgramData\chocolatey\bin",
        "C:\hostedtoolcache\windows\setup-chrome\chromedriver\stable\x64",
        $PSScriptRoot,
        "$PSScriptRoot\tools"
    )

    if ($null -ne $FoundCmd) { $PossiblePaths += Split-Path $FoundCmd.Path }

    foreach ($Path in $PossiblePaths) {
        if ($null -ne $Path -and (Test-Path "$Path\chromedriver.exe")) {
            $DriverVersion = (Get-Item "$Path\chromedriver.exe").VersionInfo.ProductVersion
            $DriverMajor = ($DriverVersion -split '\.')[0]
            if ($DesiredMajor -and $DriverMajor -ne $DesiredMajor) {
                Write-Log "chromedriver $DriverVersion does not match Chrome $ChromeVersion — ignoring $Path" -Color Yellow
                continue
            }
            Write-Log "Found chromedriver $DriverVersion at: $Path" -Color Gray
            return $Path
        }
    }

    if ($DesiredMajor) {
        Write-Log "No compatible chromedriver for Chrome $ChromeVersion — downloading matching driver..." -Color Cyan
        return Get-MatchingChromeDriver -ChromeVersion $ChromeVersion
    }

    throw "chromedriver.exe not found. Run browser-actions/setup-chrome with install-chromedriver: true in the workflow, or add chromedriver.exe to PATH."
}

function Get-MatchingChromeDriver {
    <#
    .SYNOPSIS
        Downloads the chromedriver matching the given Chrome version from
        chrome-for-testing and returns the extracted driver directory.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ChromeVersion
    )

    $Major = ($ChromeVersion -split '\.')[0]
    $Dir = Join-Path $env:TEMP "chromedriver-$ChromeVersion"
    $ExeDir = Join-Path $Dir "chromedriver-win64"

    if (Test-Path (Join-Path $ExeDir "chromedriver.exe")) {
        return $ExeDir
    }

    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $Versions = (Invoke-RestMethod -Uri "https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json").versions
    $Entry = $Versions | Where-Object { $_.version -eq $ChromeVersion } | Select-Object -First 1
    if (-not $Entry) {
        $Entry = $Versions | Where-Object { $_.version -like "$Major.*" } | Select-Object -Last 1
    }
    if (-not $Entry) { throw "No chromedriver available for Chrome $ChromeVersion." }

    $Win64 = $Entry.downloads.chromedriver | Where-Object { $_.platform -eq 'win64' } | Select-Object -First 1
    if (-not $Win64) { throw "No win64 chromedriver for Chrome $($Entry.version)." }

    $Zip = Join-Path $Dir "chromedriver.zip"
    Write-Log "Downloading chromedriver $($Entry.version)..." -Color Gray
    Invoke-WebRequest -Uri $Win64.url -UseBasicParsing -OutFile $Zip
    Expand-Archive -Path $Zip -DestinationPath $Dir -Force
    Remove-Item $Zip -Force

    return $ExeDir
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

Export-ModuleMember -Function Write-Log, Get-GeckoDriver, Get-ChromeDriver, Test-UpdateNeeded