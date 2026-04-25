$ErrorActionPreference = 'Stop'

$packageName = $env:ChocolateyPackageName
$toolsPath   = Split-Path -Parent $MyInvocation.MyCommand.Definition

$packageArgs = @{
    packageName    = $packageName
    fileType       = 'exe'
    # AU will keep this URL and checksum current on every update
    url            = 'https://downloads.nordcdn.com/apps/windows/NordVPN/8.1.2.0/NordVPNInstall.exe'
    checksum       = ''
    checksumType   = ''
    # NordVPN uses InnoSetup
    silentArgs     = '/SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS' `
                   + " /LOG=`"$($env:TEMP)\$packageName.$($env:chocolateyPackageVersion).Install.log`""
    validExitCodes = @(0)
    softwareName   = 'NordVPN*'
}

Install-ChocolateyPackage @packageArgs
