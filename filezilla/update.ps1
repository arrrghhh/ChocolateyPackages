$PackageId   = "filezilla"
$ReleasePage = "https://filezilla-project.org/download.php?show_all=1"
$ToolsDir    = "$PSScriptRoot\tools"

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

#Ensure-Module -Name 'Chocolatey-AU' # Shouldn't be needed to import this module when using GH Actions as it's already loaded...
Ensure-Module -Name 'Selenium'

Get-Module Selenium -ListAvailable

if (-not (Get-Module Selenium -ListAvailable | Where-Object Version -ge 4.0.0)) {
	& ([scriptblock]::Create((Invoke-WebRequest 'bit.ly/modulefast'))) -Specification Selenium! -NoProfileUpdate
}

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

function Get-FileZillaSHA512 {
    param(
        [Parameter(Mandatory)]
        [string] $Architecture  # "win32" or "win64"
    )

    $targetFile = "_${Architecture}-setup.exe"
    
    #Write-Host "Extracting SHA-512 for: $targetFile"
    
    # Find and click the info button for this architecture
    $infoButton = $driver.FindElement([OpenQA.Selenium.By]::XPath("//text()[contains(., '$targetFile')]/ancestor::*/following::img[@alt='Show file details'][1]"))
    $infoButton.Click()
    
    # Wait for details to appear
    [System.Threading.Thread]::Sleep(500)
    
    # Find the details div and extract SHA-512
    try {
        $sha512Element = $driver.FindElement([OpenQA.Selenium.By]::XPath("//div[@class='details']//p[contains(text(), 'SHA-512')]"))
    } catch {
        #Write-Host "XPath search failed, trying alternative method..."
        $allParagraphs = $driver.FindElements([OpenQA.Selenium.By]::XPath("//div[@class='details']//p"))
        
        $sha512Element = $null
        foreach ($para in $allParagraphs) {
            if ($para.Text -match "SHA-512") {
                $sha512Element = $para
                break
            }
        }
        
        if ($null -eq $sha512Element) {
            throw "Could not find SHA-512 hash for $targetFile"
        }
    }
    
    # Clean and extract hash
    $fullText = $sha512Element.Text
    $cleanText = $fullText -replace "\s+", " "
    
    if ($cleanText -match "SHA-512 hash:\s*([a-f0-9]{128})") {
        $sha512Value = $matches[1]
        #Write-Host "SHA-512 ($Architecture): $sha512Value"
        return $sha512Value
    } else {
        throw "Could not extract SHA-512 hash from text: $cleanText"
    }
}

function global:au_GetLatest {
    Write-Host "Starting Selenium to extract latest FileZilla URLs..."

    $Elem32 = Get-SeElement -By PartialLinkText "_win32-setup.exe"
    $URL32 = $Elem32.GetAttribute("href")

    # Parse version from URL
    $Version = ([uri]$URL32).Segments[-1].Split('_')[-2]

    if (-not ($Version -as [version])) {
        throw "Could not parse version from download URL: $URL32"
    }

    Write-Host "Found latest version: $Version"

    return @{
        Version  = $Version
        FileType = "exe"
    }
}

function global:au_BeforeUpdate {

    $Version = $Latest.Version
    Write-Host "Downloading FileZilla installers using Selenium..."

    # Clean old files
    Remove-Item "$ToolsDir\FileZilla_3*.exe" -Force -ErrorAction SilentlyContinue

    $targetFile32 = "_win32-setup.exe"
    $targetFile64 = "_win64-setup.exe"
    # Trigger real downloads (JS click)
    (Get-SeElement -By PartialLinkText $targetFile32).Click()
    (Get-SeElement -By PartialLinkText $targetFile64).Click()

    $sha512_32 = Get-FileZillaSHA512 -Architecture "win32"
    Start-Sleep -Milliseconds 500
    $sha512_64 = Get-FileZillaSHA512 -Architecture "win64"

    #Write-Host "SHA-512_32 Value: $sha512_32"
    #Write-Host "SHA-512_64 Value: $sha512_64"

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

    # Compare checksums
    if (((Get-FileHash $Local32 -Algorithm SHA512).Hash) -eq $sha512_32) {
        Write-Host "32-bit hashes match!"
    }
    else {
        Write-Error "32-bit hash mismatch, exiting..."
        exit 1
    }
    if (((Get-FileHash $Local64 -Algorithm SHA512).Hash) -eq $sha512_64) {
        Write-Host "64-bit hashes match!"
    }
    else {
        Write-Error "64-bit hash mismatch, exiting..."
        exit 1
    }
    $Latest.Checksum32 = $sha512_32
    $Latest.Checksum64 = $sha512_64
}

function global:au_SearchReplace {
    @{
        ".\legal\VERIFICATION.txt" = @{
            "(?i)(checksum32:).*" = "`${1} $($Latest.Checksum32)"
            "(?i)(checksum64:).*" = "`${1} $($Latest.Checksum64)"
        }
    }
}

$Driver = Start-SeDriver `
    -Browser "firefox" `
    -State Headless `
    -StartURL $ReleasePage `
    -DefaultDownloadPath $ToolsDir

update -ChecksumFor none -NoCheckUrl

$Driver.Quit()
$Driver.Dispose()
