$ErrorActionPreference = 'Stop'

# --- 1. Dynamic Module Loading ---
try {
    & ([scriptblock]::Create((Invoke-WebRequest 'bit.ly/modulefast' -UseBasicParsing))) -Specification 'au', 'Selenium!' -NoProfileUpdate
    Import-Module Selenium -Force
} catch {
    Write-Warning "Dynamic module loading failed: $($_.Exception.Message)"
    if (-not (Get-Module -ListAvailable au) -or -not (Get-Module -ListAvailable Selenium)) {
        throw "Required modules (au or Selenium) are missing."
    }
    Import-Module au
    Import-Module Selenium
}

# --- 2. Configuration ---
$PackageId   = "vnc-viewer"
$ReleasePage = 'https://realvnc.com/en/connect/download/viewer/'
$ToolsDir    = "$PSScriptRoot\tools"

# --- Driver Path Logic ---
function Get-GeckoDriver {
    $FoundCmd = Get-Command geckodriver.exe -ErrorAction SilentlyContinue
    $PossiblePaths = @(
        "C:\webdrivers",
        "C:\ProgramData\chocolatey\bin",
        "C:\ProgramData\chocolatey\lib\selenium-gecko-driver\tools",
        $PSScriptRoot,
        "$PSScriptRoot\tools"
    )

    if ($null -ne $FoundCmd) { $PossiblePaths += Split-Path $FoundCmd.Path }

    foreach ($path in $PossiblePaths) {
        if ($null -ne $path -and (Test-Path "$path\geckodriver.exe")) {
            return $path
        }
    }

    Write-Host "geckodriver.exe not found. Attempting automatic download..." -ForegroundColor Cyan
    $dest = Join-Path $PSScriptRoot "tools"
    if (-not (Test-Path $dest)) { New-Item $dest -ItemType Directory | Out-Null }
    
    $ghApi = "https://api.github.com/repos/mozilla/geckodriver/releases/latest"
    $release = Invoke-RestMethod $ghApi -UseBasicParsing
    $asset = $release.assets | Where-Object { $_.name -match 'win64' -and $_.name -match 'zip' } | Select-Object -First 1
    
    $zipPath = Join-Path $dest "gecko.zip"
    Invoke-WebRequest $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $dest -Force
    Remove-Item $zipPath -Force
    
    return $dest
}

$GeckoDriverDirectory = Get-GeckoDriver

# --- 3. Helper Functions ---

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $Timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$Timestamp] $Message" -ForegroundColor $Color
}

function Test-UpdateNeeded {
    param($RemoteVersion)
    # Get local version from nuspec
    $Nuspec = Get-ChildItem "$PSScriptRoot\*.nuspec" | Select-Object -First 1
    if (-not $Nuspec) { return $true }
    
    [xml]$xml = Get-Content $Nuspec.FullName
    $LocalVersion = $xml.package.metadata.version
    
    if ($LocalVersion -eq $RemoteVersion) {
        Write-Log "Local version ($LocalVersion) matches remote ($RemoteVersion). No update needed." -Color Gray
        return $false
    }
    return $true
}

function global:au_GetLatest {
    Write-Log "Navigating to: $ReleasePage"
    $Driver.Navigate().GoToUrl($ReleasePage)

    try {
        # Targeting the MSI zip download option
        $XPathQuery = "//option[contains(@data-file, '-Windows-msi.zip')]"
        $DownloadElement = $Driver.FindElement([OpenQA.Selenium.By]::XPath($XPathQuery))
        $url32 = $DownloadElement.GetAttribute("data-file")
    } catch {
        throw "Critical Failure: Could not find VNC Viewer download link. The site structure may have changed."
    }

    # Better version extraction using AU's Get-Version helper
    $versionData = Get-Version $url32
    $version = $versionData.Version

    Write-Log "Found version: $version" -Color Cyan
    
    # SHORT-CIRCUIT: Exit early if versions match
    if (-not (Test-UpdateNeeded -RemoteVersion $version)) {
        return @{ Version = $version; URL32 = $url32 }
    }

    Write-Log "Found URL: $url32"

    return @{ 
        URL32 = $url32; 
        Version = $version; 
        ChecksumType32 = 'sha256' 
    }
}

function global:au_SearchReplace {
    @{ 'tools/chocolateyInstall.ps1' = @{
        "(?i)(^\s*[$]url(?:64)?\s*=\s*)(['""].*['""])"           = "`$1'$($Latest.URL32)'"
        "(?i)(^\s*[$]checksum(?:64)?\s*=\s*)(['""].*['""])"      = "`$1'$($Latest.Checksum32)'"
        "(?i)(^\s*[$]checksumType(?:64)?\s*=\s*)(['""].*['""])"  = "`$1'sha256'"
    }}
}

# --- 4. Main Execution ---
if (-not (Test-Path $ToolsDir)) { New-Item $ToolsDir -ItemType Directory | Out-Null }

Write-Log "Initializing Firefox Headless..."
$FirefoxOptions = New-Object OpenQA.Selenium.Firefox.FirefoxOptions
$FirefoxOptions.AddArgument("--headless")
$FirefoxOptions.PageLoadStrategy = [OpenQA.Selenium.PageLoadStrategy]::None

$Driver = New-Object OpenQA.Selenium.Firefox.FirefoxDriver($GeckoDriverDirectory, $FirefoxOptions)
$Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds(10)

try {
    update -ChecksumFor 32 -NoCheckUrl
} finally {
    if ($null -ne $Driver) {
        Write-Log "Closing browser session..."
        $Driver.Quit()
        $Driver.Dispose()
    }
}