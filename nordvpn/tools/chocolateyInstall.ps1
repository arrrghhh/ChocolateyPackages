$ErrorActionPreference = 'Stop'

$packageName = $env:ChocolateyPackageName
$toolsPath   = Split-Path -Parent $MyInvocation.MyCommand.Definition

$packageArgs = @{
    packageName    = $packageName
    fileType       = 'exe'
    # AU will keep this URL and checksum current on every update
    url            = 'https://downloads.nordcdn.com/apps/windows/NordVPN/8.14.4.0/NordVPNInstall.exe'
    checksum       = 'ac41e6fb1d546c0b714222e98ba31ca70d0b813a14bb44567176cd7a165bc78b'
    checksumType   = 'sha256'
    # NordVPN uses InnoSetup -- /VERYSILENT fully suppresses UI
    silentArgs     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS'
    validExitCodes = @(0)
    softwareName   = 'NordVPN*'
}

Install-ChocolateyPackage @packageArgs
