$ErrorActionPreference = 'Stop'

$packageName = $env:ChocolateyPackageName
$toolsPath   = Split-Path -Parent $MyInvocation.MyCommand.Definition

$packageArgs = @{
    packageName    = $packageName
    fileType       = 'exe'
    # AU will keep this URL and checksum current on every update
    url            = 'https://downloads.nordcdn.com/apps/windows/NordVPN/8.11.1.0/NordVPNInstall.exe'
    checksum       = '61fe06d530d6012f329f8031ea204241a55fccaf136ce38325cbd566355c155c'
    checksumType   = 'sha256'
    # NordVPN uses InnoSetup -- /VERYSILENT fully suppresses UI
    silentArgs     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS'
    validExitCodes = @(0)
    softwareName   = 'NordVPN*'
}

Install-ChocolateyPackage @packageArgs
