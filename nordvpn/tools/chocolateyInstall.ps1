$ErrorActionPreference = 'Stop'

$packageName = $env:ChocolateyPackageName
$toolsPath   = Split-Path -Parent $MyInvocation.MyCommand.Definition

$packageArgs = @{
    packageName    = $packageName
    fileType       = 'exe'
    # AU will keep this URL and checksum current on every update
    url            = 'https://downloads.nordcdn.com/apps/windows/NordVPN/8.10.3.0/NordVPNInstall.exe'
    checksum       = '5418ee00763f83a6bb613fe8563cffba7e2fcf29d05a24b7bafb9b05cbc3bfc2'
    checksumType   = 'sha256'
    # NordVPN uses InnoSetup -- /VERYSILENT fully suppresses UI
    silentArgs     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS'
    validExitCodes = @(0)
    softwareName   = 'NordVPN*'
}

Install-ChocolateyPackage @packageArgs
