$ErrorActionPreference = 'Stop'

# Import shared helpers (Write-Log, Test-UpdateNeeded)
Import-Module "$PSScriptRoot\..\helpers.psm1" -Force

# --- 1. Module Loading ---
if (-not (Get-Module -ListAvailable Selenium)) {
    Install-Module Selenium -Force -Scope CurrentUser -AllowClobber
}
Import-Module Selenium -Force

# --- 2. Configuration ---
$ReleasePage = 'https://realvnc.com/en/connect/download/viewer/'

# --- 3. AU Functions ---

function global:au_GetLatest {
    Write-Log "Navigating to: $ReleasePage"
    $global:Driver.Navigate().GoToUrl($ReleasePage)

    # Cloudflare's JS challenge needs a few seconds to resolve and redirect
    # to the real page before the config JSON is present in the DOM. Poll for
    # the config script itself rather than guessing at challenge markers.
    $Timeout = 30
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
    }

    $Match = [regex]::Match(
        $PageSource,
        '<script type="application/json" class="rvnc-mass-config"[^>]*>(?<json>.*?)</script>',
        'Singleline'
    )
    if (-not $Match.Success) {
        throw "Critical Failure: Could not find rvnc-mass-config JSON block. Either the Cloudflare challenge didn't clear in time, or the site structure changed."
    }

    $Config = $Match.Groups['json'].Value | ConvertFrom-Json
    $ViewerWindows = $Config.index.products.'realvnc-connect-viewer'.platforms.windows
    $ZipFile = $ViewerWindows.files | Where-Object { $_.pkg -eq 'zip' } | Select-Object -First 1

    if (-not $ZipFile) {
        throw "Critical Failure: No Windows zip package found for realvnc-connect-viewer in config JSON."
    }

    $version = $ZipFile.version
    Write-Log "Found version: $version" -Color Cyan

    $url = "https://downloads.realvnc.com/download/file/realvnc-connect-viewer/$($ZipFile.file)"

    if (-not (Test-UpdateNeeded -RemoteVersion $version -PackageDir $PSScriptRoot)) {
        return @{ Version = $version; URL32 = $url }
    }

    return @{
        URL32          = $url
        Version        = $version
        Checksum32     = $ZipFile.sha256
        ChecksumType32 = 'sha256'
    }
}

function global:au_SearchReplace {
    @{ 'tools/chocolateyInstall.ps1' = @{
        "(?i)(^\s*[$]url(?:64)?\s*=\s*)(['""].*['""])"          = "`$1'$($Latest.URL32)'"
        "(?i)(^\s*[$]checksum(?:64)?\s*=\s*)(['""].*['""])"     = "`$1'$($Latest.Checksum32)'"
        "(?i)(^\s*[$]checksumType(?:64)?\s*=\s*)(['""].*['""])" = "`$1'sha256'"
    }}
}

# --- 4. Main Execution ---
Write-Log "Initializing Chrome (headful, software WebGL)..."

$ChromeDriverDirectory = Get-ChromeDriver

$ChromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
# Chrome runs headed (no --headless). Cloudflare's bot detection 403s
# headless Chrome even from residential IPs, but headed Chrome passes.
Write-Log "Chrome headful mode" -Color Gray
$ChromeOptions.AddArgument("--window-size=1920,1080")
$ChromeOptions.AddArgument("--enable-unsafe-swiftshader")
$ChromeOptions.AddArgument("--disable-blink-features=AutomationControlled")
$ChromeOptions.AddExcludedArgument("enable-automation")
$ChromeOptions.PageLoadStrategy = [OpenQA.Selenium.PageLoadStrategy]::Eager

# Point ChromeDriver at the Chrome binary installed by browser-actions/setup-chrome
# (avoids Selenium Manager, which ignores PATH chromedriver and can pick a stale one).
$ChromeExe = (Get-Command chrome.exe -ErrorAction SilentlyContinue).Source
if ($ChromeExe) {
    Write-Log "Chrome binary: $ChromeExe" -Color Gray
    $ChromeOptions.BinaryLocation = $ChromeExe
}

$global:Driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($ChromeDriverDirectory, $ChromeOptions)
$global:Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds(10)

$MaxAttempts = 3

try {
    $result = $null
    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        try {
            $result = update -ChecksumFor none
            break
        } catch {
            Write-Log "Attempt ${Attempt}/${MaxAttempts} failed: $($_.Exception.Message)" -Color Red
            if ($Attempt -eq $MaxAttempts) { throw }
            $WaitSec = 30 * $Attempt   # 30s, then 60s
            Write-Log "Backing off for ${WaitSec}s before retry..." -Color Yellow
            Start-Sleep -Seconds $WaitSec
        }
    }

    if ($Push -and $result.Updated) {
        $nupkg = Get-ChildItem "$PSScriptRoot\*.nupkg" | Select-Object -First 1
        choco push $nupkg.FullName --source https://push.chocolatey.org/
    }
} finally {
    if ($null -ne $global:Driver) {
        Write-Log "Closing browser session..."
        $global:Driver.Quit()
        $global:Driver.Dispose()
    }
}