$ErrorActionPreference = 'Stop'

$packageName = $env:ChocolateyPackageName
$toolsPath   = Split-Path -Parent $MyInvocation.MyCommand.Definition

$packageArgs = @{
    packageName    = $packageName
    fileType       = 'exe'
    # AU will keep this URL and checksum current on every update
    url            = 'https://downloads.nordcdn.com/apps/windows/NordVPN/8.1.2.0/NordVPNInstall.exe'
    checksum       = '0b34bc0173cbaf396b6dcfd753e6dc0f1201abf0495495bcfb27cd903a27f9f5'
    checksumType   = 'sha256'
    # NordVPN uses InnoSetup -- /VERYSILENT fully suppresses UI
    silentArgs     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS'
    validExitCodes = @(0)
    softwareName   = 'NordVPN*'
}

Install-ChocolateyPackage @packageArgs