$ErrorActionPreference = 'Stop'

# Import shared helpers (Write-Log, Get-GeckoDriver, Test-UpdateNeeded)
Import-Module "$PSScriptRoot\..\helpers.psm1" -Force

# --- 1. Module Loading ---
if (-not (Get-Module -ListAvailable Selenium)) {
    Install-Module Selenium -Force -Scope CurrentUser -AllowClobber
}
Import-Module Selenium -Force

# --- 2. Configuration ---
$PackageId   = "filezilla"
$ReleasePage = 'https://filezilla-project.org/download.php?show_all=1'
$ToolsDir    = "$PSScriptRoot\tools"
$MaxAttempts = 3

$GeckoDriverDirectory = Get-GeckoDriver

# --- 3. Helper Functions ---

function Start-Backoff {
    param([int]$Attempt)
    $WaitSec = [Math]::Pow(2, $Attempt)
    Write-Log "Backing off for ${WaitSec}s before retry..." -Color Yellow
    Start-Sleep -Seconds $WaitSec
}

function Get-FileZillaSHA512 {
    param([string]$FullFileName)

    if ([string]::IsNullOrWhiteSpace($FullFileName)) {
        throw "Get-FileZillaSHA512: Received an empty filename."
    }

    $DetailsUrl = "https://filezilla-project.org/download.php?details=$FullFileName"

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            Write-Log "Attempt ${i}: Fetching hash page for $FullFileName" -Color Cyan
            $global:Driver.Navigate().GoToUrl($DetailsUrl)

            if ($global:Driver.PageSource -match "([a-f0-9]{128})") {
                $Hash = $matches[1]
                Write-Log "Hash extracted: $Hash" -Color Green
                return $Hash
            }

            throw "SHA-512 hash not found in page source of $DetailsUrl"
        } catch {
            Write-Log "Attempt ${i} failed: $($_.Exception.Message)" -Color Red
            if ($i -eq $MaxAttempts) { throw }
            Start-Backoff -Attempt $i
        }
    }
}

# --- 4. AU Functions ---

function global:au_GetLatest {
    Write-Log "Navigating to: $ReleasePage"
    $global:Driver.Navigate().GoToUrl($ReleasePage)

    $link64 = $null
    $link32 = $null
    $file64 = $null
    $file32 = $null

    try {
        $el64   = $global:Driver.FindElement([OpenQA.Selenium.By]::XPath("//a[contains(@href, 'win64-setup.exe') and not(contains(@href, 'patched'))]"))
        $link64 = $el64.GetAttribute("href")
        if ($link64 -match "/([^/?]+)(?:\?|$)") {
            $file64 = $matches[1]
            Write-Log "64-bit filename: $file64"
        }

        $el32   = $global:Driver.FindElement([OpenQA.Selenium.By]::XPath("//a[contains(@href, 'win32-setup.exe')]"))
        $link32 = $el32.GetAttribute("href")
        if ($link32 -match "/([^/?]+)(?:\?|$)") {
            $file32 = $matches[1]
            Write-Log "32-bit filename: $file32"
        }
    } catch {
        throw "Critical Failure: Could not locate download links. The page structure may have changed."
    }

    $version = (Get-Version $link64).Version
    Write-Log "Remote version: $version" -Color Cyan

    # Short-circuit: skip expensive hash scraping if version hasn't changed
    if (-not (Test-UpdateNeeded -RemoteVersion $version -PackageDir $PSScriptRoot)) {
        return @{ Version = $version; URL64 = $link64; URL32 = $link32 }
    }

    $hash64 = Get-FileZillaSHA512 -FullFileName $file64
    $hash32 = Get-FileZillaSHA512 -FullFileName $file32

    Write-Log "64-bit URL : $link64" -Color Magenta
    Write-Log "32-bit URL : $link32" -Color Magenta

    return @{
        URL64          = $link64;  URL32          = $link32
        Version        = $version
        Checksum64     = $hash64;  Checksum32     = $hash32
        ChecksumType64 = 'sha512'; ChecksumType32 = 'sha512'
        FileType       = 'exe'
    }
}

function global:au_SearchReplace {
    @{
        'legal/VERIFICATION.txt' = @{
            '(?i)(Version:\s*)[\d.]+'                         = "`${1}$($Latest.Version)"
            '(?i)(checksum64:\s*)[a-f0-9]{128}'              = "`${1}$($Latest.Checksum64)"
            '(?i)(checksum32:\s*)[a-f0-9]{128}'              = "`${1}$($Latest.Checksum32)"
        }
    }
}

function global:au_BeforeUpdate {
    Write-Log "Cleaning old installers from tools\..." -Color Cyan
    Get-ChildItem "$ToolsDir\*.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'geckodriver.exe' } |
        Remove-Item -Force

    # Navigate to the release page first so the browser has a valid page context,
    # then trigger downloads via JS. Using GoToUrl() directly on a CDN file URL
    # blocks the driver indefinitely waiting for a page load that never arrives.
    Write-Log "Navigating to release page for download context..." -Color Cyan
    $global:Driver.Navigate().GoToUrl($ReleasePage)

    Write-Log "Triggering 64-bit download via JS..." -Color Cyan
    $global:Driver.ExecuteScript("window.location.href = arguments[0]", $Latest.URL64)
    Start-Sleep -Seconds 5

    Write-Log "Triggering 32-bit download via JS..." -Color Cyan
    $global:Driver.ExecuteScript("window.location.href = arguments[0]", $Latest.URL32)
    Start-Sleep -Seconds 5

    # Wait for both named EXEs to appear with no in-progress .part files
    $Timeout = 180
    $Elapsed = 0
    $Ver     = $Latest.Version

    Write-Log "Waiting for downloads to complete (timeout: ${Timeout}s)..." -Color Cyan
    do {
        Start-Sleep -Seconds 3
        $Elapsed  += 3
        $PartFiles = Get-ChildItem "$ToolsDir\*.part" -ErrorAction SilentlyContinue
        $Done64    = Get-ChildItem "$ToolsDir\FileZilla_${Ver}_win64-setup.exe" -ErrorAction SilentlyContinue
        $Done32    = Get-ChildItem "$ToolsDir\FileZilla_${Ver}_win32-setup.exe" -ErrorAction SilentlyContinue

        if ($Elapsed -ge $Timeout) {
            throw "Timed out after ${Timeout}s waiting for downloads. " +
                  "64-bit: $($null -ne $Done64), 32-bit: $($null -ne $Done32)"
        }
    } while ($PartFiles -or -not $Done64 -or -not $Done32)

    Write-Log "Downloads complete: $($Done64.Name), $($Done32.Name)" -Color Green
}

# --- 5. Main Execution ---
if (-not (Test-Path $ToolsDir)) { New-Item $ToolsDir -ItemType Directory | Out-Null }

Write-Log "Initializing Firefox (headless)..."
$FirefoxOptions = New-Object OpenQA.Selenium.Firefox.FirefoxOptions
$FirefoxOptions.AddArgument("--headless")
$FirefoxOptions.PageLoadStrategy = [OpenQA.Selenium.PageLoadStrategy]::Eager

# Configure Firefox to auto-download EXEs to tools\ without prompting
$FirefoxOptions.SetPreference("browser.download.folderList",                    2)
$FirefoxOptions.SetPreference("browser.download.dir",                           $ToolsDir)
$FirefoxOptions.SetPreference("browser.download.useDownloadDir",                $true)
$FirefoxOptions.SetPreference("browser.helperApps.neverAsk.saveToDisk",        "application/octet-stream,application/x-msdownload,application/x-msdos-program,application/exe,application/x-exe")
$FirefoxOptions.SetPreference("browser.download.manager.showWhenStarting",     $false)
$FirefoxOptions.SetPreference("browser.download.improvements_to_download_panel", $false)

$global:Driver = New-Object OpenQA.Selenium.Firefox.FirefoxDriver($GeckoDriverDirectory, $FirefoxOptions)
$global:Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds(10)

try {
    $result = update -ChecksumFor none -NoCheckUrl -NoCheckChocoVersion
    if ($Push -and $result.Updated) { Push-Package }
} finally {
    if ($null -ne $global:Driver) {
        Write-Log "Closing browser session..."
        $global:Driver.Quit()
        $global:Driver.Dispose()
    }
}