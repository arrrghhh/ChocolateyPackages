$ErrorActionPreference = 'Stop'

# Import shared helpers (Write-Log, Test-UpdateNeeded)
Import-Module "$PSScriptRoot\..\helpers.psm1" -Force

# --- 1. Configuration ---
$ReleasePage = 'https://realvnc.com/en/connect/download/viewer/'

# RealVNC's download page is behind a Cloudflare bot challenge that blocks
# GitHub Actions runners outright (headful Chrome included). The winget-pkgs
# manifest carries the exact same installer URL and SHA256 and is served by
# GitHub, so it is the primary source. The page scrape stays as a fallback.
# Trade-off: winget can lag a fresh RealVNC release by a few days.
$WingetManifestRoot = 'manifests/r/RealVNC/VNCConnect/Viewer'
$WingetPackageId = 'RealVNC.VNCConnect.Viewer'

# --- 2. Latest version from winget-pkgs (Cloudflare-free) ---

function Get-VncLatestFromWinget {
    <#
    .SYNOPSIS
        Reads the newest RealVNC.VNCConnect.Viewer manifest from winget-pkgs.

    .DESCRIPTION
        Uses the GitHub contents API to find the newest version directory, then
        reads the installer manifest for the Windows zip URL and its SHA256.
    #>
    $Headers = @{
        'User-Agent' = 'arrrghhh-chocolatey-au'
        'Accept'     = 'application/vnd.github+json'
    }
    $Token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } elseif ($env:github_token) { $env:github_token } else { $null }
    if ($Token) { $Headers['Authorization'] = "Bearer $Token" }

    $Listing = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-pkgs/contents/$WingetManifestRoot" -Headers $Headers
    $LatestDir = $Listing |
        Where-Object { $_.type -eq 'dir' -and $_.name -match '^\d+(\.\d+)+$' } |
        Sort-Object { [version]$_.name } |
        Select-Object -Last 1
    if (-not $LatestDir) {
        throw "No version directories found under $WingetManifestRoot"
    }

    $ManifestUrl = "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/$WingetManifestRoot/$($LatestDir.name)/$WingetPackageId.installer.yaml"
    $Manifest = (Invoke-WebRequest -Uri $ManifestUrl -Headers @{ 'User-Agent' = 'arrrghhh-chocolatey-au' }).Content

    # Only consider the Windows installer zip entries; prefer x64.
    $Entries = [regex]::Matches(
        $Manifest,
        '(?ms)^- Architecture:\s*(?<arch>\S+).*?^\s*InstallerUrl:\s*(?<url>\S+).*?^\s*InstallerSha256:\s*(?<sha>[0-9a-fA-F]{64})'
    ) | ForEach-Object {
        [PSCustomObject]@{
            Arch = $_.Groups['arch'].Value
            Url  = $_.Groups['url'].Value
            Sha  = $_.Groups['sha'].Value
        }
    } | Where-Object { $_.Url -match '\.msi\.zip$' }

    $Entry = $Entries | Where-Object { $_.Arch -eq 'x64' } | Select-Object -First 1
    if (-not $Entry) { $Entry = $Entries | Select-Object -First 1 }
    if (-not $Entry) {
        throw "No Windows msi.zip installer found in winget manifest $ManifestUrl"
    }

    # The package version is the three-part viewer version embedded in the file
    # name (RealVNC-Connect-Viewer-8.6.0-Windows.msi.zip), not winget's
    # four-part PackageVersion (8.6.0.15).
    if ($Entry.Url -match 'RealVNC-Connect-Viewer-(?<version>\d+(?:\.\d+)+)-Windows') {
        $Version = $Matches['version']
    } else {
        $Version = ($LatestDir.name -split '\.' | Select-Object -First 3) -join '.'
    }

    Write-Log "Winget manifest $($LatestDir.name) -> version $Version" -Color Cyan

    return @{
        Version        = $Version
        URL32          = $Entry.Url
        Checksum32     = $Entry.Sha
        ChecksumType32 = 'sha256'
    }
}

# --- 3. Chrome session helper ---

function New-VncChromeSession {
    <#
    .SYNOPSIS
        Starts a fresh headful ChromeDriver session (page-scrape fallback only).

    .DESCRIPTION
        Headful is used because Cloudflare 403s headless Chrome. A fresh session
        per attempt avoids a Cloudflare 403 from one session poisoning the next.
    #>
    if ($null -ne $global:Driver) {
        Write-Log "Closing previous Chrome session..." -Color Gray
        try { $global:Driver.Quit() } catch { }
        try { $global:Driver.Dispose() } catch { }
    }

    $ChromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
    Write-Log "Chrome headful mode" -Color Gray
    $ChromeOptions.AddArgument("--window-size=1920,1080")
    $ChromeOptions.AddArgument("--enable-unsafe-swiftshader")
    $ChromeOptions.AddArgument("--disable-blink-features=AutomationControlled")
    $ChromeOptions.AddExcludedArgument("enable-automation")
    $ChromeOptions.PageLoadStrategy = [OpenQA.Selenium.PageLoadStrategy]::Eager

    # Point ChromeDriver at the Chrome binary installed by browser-actions/setup-chrome
    # (avoids Selenium Manager, which ignores PATH chromedriver and can pick a stale one).
    $ChromeExe = (Get-Command chrome.exe -ErrorAction SilentlyContinue).Source
    $ChromeVersion = $null
    if ($ChromeExe) {
        Write-Log "Chrome binary: $ChromeExe" -Color Gray
        $ChromeOptions.BinaryLocation = $ChromeExe
        $ChromeVersion = (Get-Item $ChromeExe).VersionInfo.ProductVersion
        Write-Log "Chrome version: $ChromeVersion" -Color Gray
    }

    # Get a chromedriver that matches the installed Chrome. If setup-chrome's
    # "stable" driver drifts from the actual Chrome (e.g. image cache lags), a
    # matching driver is downloaded automatically.
    $ChromeDriverDirectory = Get-ChromeDriver -ChromeVersion $ChromeVersion

    $global:Driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($ChromeDriverDirectory, $ChromeOptions)
    $global:Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds(10)
}

# --- 4. Fallback: scrape the download page ---

function Get-VncLatestFromPage {
    <#
    .SYNOPSIS
        Scrapes realvnc.com for the rvnc-mass-config JSON block.
    #>
    if (-not (Get-Module -ListAvailable Selenium)) {
        Install-Module Selenium -Force -Scope CurrentUser -AllowClobber
    }
    Import-Module Selenium -Force

    Write-Log "Initializing Chrome (headful, software WebGL)..."
    New-VncChromeSession

    try {
        Write-Log "Navigating to: $ReleasePage"
        $global:Driver.Navigate().GoToUrl($ReleasePage)

        # Cloudflare's JS challenge needs a few seconds to resolve and redirect
        # to the real page before the config JSON is present in the DOM. Poll for
        # the config script itself rather than guessing at challenge markers.
        $Timeout = 60
        $Elapsed = 0
        while ($Elapsed -lt $Timeout) {
            $PageSource = $global:Driver.PageSource
            if ($PageSource -match 'rvnc-mass-config') { break }
            Start-Sleep -Seconds 2
            $Elapsed += 2
        }

        $PageSource = $global:Driver.PageSource

        if ($PageSource -notmatch 'rvnc-mass-config') {
            $HasChallenge = [bool]($PageSource -match 'Just a moment|challenge-platform|Verify you are human|cf-chl|Turnstile')
            Write-Log "Config not found. Page title: '$($global:Driver.Title)'. Challenge markers present: $HasChallenge" -Color Yellow
            throw "Critical Failure: Could not find rvnc-mass-config JSON block. Either the Cloudflare challenge didn't clear in time, or the site structure changed."
        }

        $Match = [regex]::Match(
            $PageSource,
            '<script type="application/json" class="rvnc-mass-config"[^>]*>(?<json>.*?)</script>',
            'Singleline'
        )
        if (-not $Match.Success) {
            throw "Critical Failure: Could not parse the rvnc-mass-config JSON block."
        }

        $Config = $Match.Groups['json'].Value | ConvertFrom-Json
        $ViewerWindows = $Config.index.products.'realvnc-connect-viewer'.platforms.windows
        $ZipFile = $ViewerWindows.files | Where-Object { $_.pkg -eq 'zip' } | Select-Object -First 1

        if (-not $ZipFile) {
            throw "Critical Failure: No Windows zip package found for realvnc-connect-viewer in config JSON."
        }

        Write-Log "Found version: $($ZipFile.version)" -Color Cyan

        return @{
            Version        = $ZipFile.version
            URL32          = "https://downloads.realvnc.com/download/file/realvnc-connect-viewer/$($ZipFile.file)"
            Checksum32     = $ZipFile.sha256
            ChecksumType32 = 'sha256'
        }
    } finally {
        if ($null -ne $global:Driver) {
            Write-Log "Closing browser session..." -Color Gray
            try { $global:Driver.Quit() } catch { }
            try { $global:Driver.Dispose() } catch { }
            $global:Driver = $null
        }
    }
}

# --- 5. AU Functions ---

function global:au_GetLatest {
    $Latest = $null

    try {
        $Latest = Get-VncLatestFromWinget
    } catch {
        Write-Log "Winget manifest lookup failed: $($_.Exception.Message)" -Color Yellow
        Write-Log "Falling back to scraping the download page..." -Color Yellow
        $Latest = Get-VncLatestFromPage
    }

    if (-not (Test-UpdateNeeded -RemoteVersion $Latest.Version -PackageDir $PSScriptRoot)) {
        return @{ Version = $Latest.Version; URL32 = $Latest.URL32 }
    }

    return $Latest
}

function global:au_SearchReplace {
    @{ 'tools/chocolateyInstall.ps1' = @{
        "(?i)(^\s*[$]url(?:64)?\s*=\s*)(['""].*['""])"          = "`$1'$($Latest.URL32)'"
        "(?i)(^\s*[$]checksum(?:64)?\s*=\s*)(['""].*['""])"     = "`$1'$($Latest.Checksum32)'"
        "(?i)(^\s*[$]checksumType(?:64)?\s*=\s*)(['""].*['""])" = "`$1'sha256'"
    }}
}

# --- 6. Main Execution ---
$MaxAttempts = 3

$result = $null
for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
    try {
        $result = update -ChecksumFor none
        break
    } catch {
        Write-Log "Attempt ${Attempt}/${MaxAttempts} failed: $($_.Exception.Message)" -Color Red
        if ($Attempt -eq $MaxAttempts) { throw }
        $WaitSec = [int](15 * [Math]::Pow(2, $Attempt - 1))   # 15s, 30s
        Write-Log "Backing off for ${WaitSec}s before retry..." -Color Yellow
        Start-Sleep -Seconds $WaitSec
    }
}

if ($Push -and $result.Updated) {
    $nupkg = Get-ChildItem "$PSScriptRoot\*.nupkg" | Select-Object -First 1
    choco push $nupkg.FullName --source https://push.chocolatey.org/
}
