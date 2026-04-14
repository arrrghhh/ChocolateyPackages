param([switch]$Push)

$ErrorActionPreference = 'Stop'

# Import shared helpers (Write-Log, Get-GeckoDriver, Test-UpdateNeeded)
Import-Module "$PSScriptRoot\..\helpers.psm1" -Force

# --- 1. Module Loading ---
if (-not (Get-Module -ListAvailable Selenium)) {
    Install-Module Selenium -Force -Scope CurrentUser -AllowClobber
}
Import-Module Selenium -Force

# --- 2. Configuration ---
$PackageId   = "vnc-viewer"
$ReleasePage = 'https://realvnc.com/en/connect/download/viewer/'
$ToolsDir    = "$PSScriptRoot\tools"

$GeckoDriverDirectory = Get-GeckoDriver

# --- 3. AU Functions ---

function global:au_GetLatest {
    Write-Log "Navigating to: $ReleasePage"
    $global:Driver.Navigate().GoToUrl($ReleasePage)

    try {
        $XPathQuery    = "//option[contains(@data-file, '-Windows-msi.zip')]"
        $DownloadElement = $global:Driver.FindElement([OpenQA.Selenium.By]::XPath($XPathQuery))
        $url32         = $DownloadElement.GetAttribute("data-file")
    } catch {
        throw "Critical Failure: Could not find VNC Viewer download link. The site structure may have changed."
    }

    $version = (Get-Version $url32).Version
    Write-Log "Found version: $version" -Color Cyan

    # Short-circuit: skip expensive operations if version hasn't changed
    if (-not (Test-UpdateNeeded -RemoteVersion $version -PackageDir $PSScriptRoot)) {
        return @{ Version = $version; URL32 = $url32 }
    }

    Write-Log "Found URL: $url32"

    return @{
        URL32          = $url32
        Version        = $version
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
if (-not (Test-Path $ToolsDir)) { New-Item $ToolsDir -ItemType Directory | Out-Null }

Write-Log "Initializing Firefox (headless)..."
$FirefoxOptions = New-Object OpenQA.Selenium.Firefox.FirefoxOptions
$FirefoxOptions.AddArgument("--headless")
$FirefoxOptions.PageLoadStrategy = [OpenQA.Selenium.PageLoadStrategy]::Eager

$global:Driver = New-Object OpenQA.Selenium.Firefox.FirefoxDriver($GeckoDriverDirectory, $FirefoxOptions)
$global:Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds(10)

try {
    if ($Push) { update -ChecksumFor 32 -Push } else { update -ChecksumFor 32 }
} finally {
    if ($null -ne $global:Driver) {
        Write-Log "Closing browser session..."
        $global:Driver.Quit()
        $global:Driver.Dispose()
    }
}