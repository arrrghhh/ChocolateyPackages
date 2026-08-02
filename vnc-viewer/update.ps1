$ErrorActionPreference = 'Stop'

# Import shared helpers (Write-Log, Get-GeckoDriver, Test-UpdateNeeded)
Import-Module "$PSScriptRoot\..\helpers.psm1" -Force

# --- 1. Module Loading ---
if (-not (Get-Module -ListAvailable Selenium)) {
    Install-Module Selenium -Force -Scope CurrentUser -AllowClobber
}
Import-Module Selenium -Force

# --- 2. Configuration ---
$ReleasePage = 'https://realvnc.com/en/connect/download/viewer/'
$ToolsDir    = "$PSScriptRoot\tools"

$GeckoDriverDirectory = Get-GeckoDriver

# --- 3. AU Functions ---

function global:au_GetLatest {
    Write-Log "Fetching: $ReleasePage"
    $Response = Invoke-WebRequest -Uri $ReleasePage -UseBasicParsing

    $Match = [regex]::Match(
        $Response.Content,
        '<script type="application/json" class="rvnc-mass-config"[^>]*>(?<json>.*?)</script>',
        'Singleline'
    )
    if (-not $Match.Success) {
        throw "Critical Failure: Could not find rvnc-mass-config JSON block. The page structure may have changed."
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
try {
    $result = update -ChecksumFor none
    if ($Push -and $result.Updated) {
        $nupkg = Get-ChildItem "$PSScriptRoot\*.nupkg" | Select-Object -First 1
        choco push $nupkg.FullName --source https://push.chocolatey.org/
    }
} catch {
    throw
}