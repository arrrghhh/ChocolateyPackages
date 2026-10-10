$ErrorActionPreference = 'Stop'

$packageName = $env:ChocolateyPackageName
$toolsPath   = Split-Path -Parent $MyInvocation.MyCommand.Definition

$packageArgs = @{
    packageName    = $packageName
    fileType       = 'exe'
    # AU will keep this URL and checksum current on every update
    url            = 'https://downloads.nordcdn.com/apps/windows/NordVPN/8.13.1.0/NordVPNInstall.exe'
    checksum       = '1aaad918bf4a7afc4a1a6bfce4e73f86f2c1c0ac505193a6b0a610c879f6f823'
    checksumType   = 'sha256'
    # NordVPN uses InnoSetup -- /VERYSILENT fully suppresses UI
    silentArgs     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS'
    validExitCodes = @(0)
    softwareName   = 'NordVPN*'
}

Install-ChocolateyPackage @packageArgs
