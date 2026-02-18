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
$PackageId   = "filezilla"
$ReleasePage = 'https://filezilla-project.org/download.php?show_all=1'
$ToolsDir    = "$PSScriptRoot\tools"
$MaxAttempts = 3 

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

function Start-Backoff {
    param([int]$Attempt)
    $waitSec = [Math]::Pow(2, $Attempt)
    Write-Log "Backing off for ${waitSec} seconds (Network Retry)..." -Color Yellow
    Start-Sleep -Seconds $waitSec
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

function Get-FileZillaSHA512 {
    param([string]$FullFileName)
    
    if ([string]::IsNullOrWhiteSpace($FullFileName)) {
        throw "Get-FileZillaSHA512: Received an empty filename. Cannot generate details URL."
    }

    $DetailsUrl = "https://filezilla-project.org/download.php?details=$FullFileName"
    
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            Write-Log "Attempt ${i}: Navigating to hash page for $FullFileName" -Color Cyan
            $Driver.Navigate().GoToUrl($DetailsUrl)
            
            $PageSource = $Driver.PageSource
            if ($PageSource -match "([a-f0-9]{128})") {
                $hash = $matches[1]
                Write-Log "Successfully extracted hash: $hash" -Color Green
                return $hash
            }
            
            throw "SHA-512 hash not found in page source of $DetailsUrl"
        } catch {
            Write-Log "Attempt ${i} failed: $($_.Exception.Message)" -Color Red
            if ($i -eq $MaxAttempts) { throw }
            Start-Backoff -Attempt $i
        }
    }
}

function global:au_GetLatest {
    Write-Log "Navigating to: $ReleasePage"
    $Driver.Navigate().GoToUrl($ReleasePage)
    
    $link64 = $null
    $link32 = $null
    $file64 = $null
    $file32 = $null

    try {
        $el64 = $Driver.FindElement([OpenQA.Selenium.By]::XPath("//a[contains(@href, 'win64-setup.exe') and not(contains(@href, 'patched'))]"))
        $link64 = $el64.GetAttribute("href")
        
        if ($link64 -match "/([^/?]+)(?:\?|$)") { 
            $file64 = $matches[1] 
            Write-Log "Detected 64-bit filename: $file64"
        }

        $el32 = $Driver.FindElement([OpenQA.Selenium.By]::XPath("//a[contains(@href, 'win32-setup.exe')]"))
        $link32 = $el32.GetAttribute("href")
        if ($link32 -match "/([^/?]+)(?:\?|$)") { 
            $file32 = $matches[1] 
            Write-Log "Detected 32-bit filename: $file32"
        }
    } catch {
        throw "Critical Failure: Could not locate download links on the main page."
    }

    $version = (Get-Version $link64).Version
    Write-Log "Remote Version Detected: $version" -Color Cyan
    
    # SHORT-CIRCUIT: Check local version vs remote before doing intensive scraping
    if (-not (Test-UpdateNeeded -RemoteVersion $version)) {
         return @{ Version = $version; URL64 = $link64; URL32 = $link32 }
    }

    # Extract hashes only if update is actually needed
    $hash64 = Get-FileZillaSHA512 -FullFileName $file64
    $hash32 = Get-FileZillaSHA512 -FullFileName $file32

    Write-Log "--- Scrape Results Summary ---" -Color Magenta
    Write-Log "Version: $version"
    Write-Log "64-bit URL: $link64"
    Write-Log "32-bit URL: $link32"
    Write-Log "------------------------------"

    return @{ 
        URL64 = $link64; URL32 = $link32; Version = $version; 
        Checksum64 = $hash64;
        Checksum32 = $hash32;
        ChecksumType64 = 'sha512'; ChecksumType32 = 'sha512'
    }
}

function global:au_SearchReplace {
    @{ 'tools/chocolateyInstall.ps1' = @{
        "(?i)(^\s*[$]url\s*=\s*)(['""].*['""])"      = "`$1'$($Latest.URL32)'"
        "(?i)(^\s*[$]checksum\s*=\s*)(['""].*['""])" = "`$1'$($Latest.Checksum32)'"
        "(?i)(^\s*[$]url64\s*=\s*)(['""].*['""])"    = "`$1'$($Latest.URL64)'"
        "(?i)(^\s*[$]checksum64\s*=\s*)(['""].*['""])" = "`$1'$($Latest.Checksum64)'"
    }}
}

# --- 4. Main Execution ---
if (-not (Test-Path $ToolsDir)) { New-Item $ToolsDir -ItemType Directory }

Write-Log "Initializing Firefox via .NET..."
$FirefoxOptions = New-Object OpenQA.Selenium.Firefox.FirefoxOptions
$FirefoxOptions.AddArgument("--headless")
$FirefoxOptions.PageLoadStrategy = [OpenQA.Selenium.PageLoadStrategy]::None

$Driver = New-Object OpenQA.Selenium.Firefox.FirefoxDriver($GeckoDriverDirectory, $FirefoxOptions)
$Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds(10)

try {
    update -ChecksumFor none -NoCheckUrl
} finally {
    if ($null -ne $Driver) {
        Write-Log "Closing browser session..."
        $Driver.Quit()
        $Driver.Dispose()
    }
}