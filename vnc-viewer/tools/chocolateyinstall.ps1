# https://www.realvnc.com/en/connect/download/viewer/
$ErrorActionPreference = 'Stop'
$packageName    = 'vnc-viewer'
$toolsDir       = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$extractDir     = "$toolsDir\extracted"
$url            = 'https://downloads.realvnc.com/download/file/realvnc-connect-viewer/RealVNC-Connect-Viewer-8.6.0-Windows.msi.zip'
$checksum       = '538a9a1c5a80bd5d163d2af9e0c04a2177f7df5a7a88f25cacf7405056741e54'
$checksumType   = 'sha256'

$packageArgs = @{
  packageName   = $packageName
  unzipLocation = $extractDir
  fileType      = 'ZIP' 
  url           = $url
  checksum      = $checksum
  checksumType  = $checksumType
}

Install-ChocolateyZipPackage @packageArgs 

$Installer = (Get-ChildItem -Path $extractDir -Filter '*.msi' | Select-Object -First 1).FullName
if (-not $Installer) { throw "Could not locate an MSI installer in $extractDir after extraction." }

$packageArgs = @{
  packageName    = $packageName
  fileType       = 'MSI'
  file           = $Installer
  silentArgs     = '/quiet /qn /norestart'
  validExitCodes = @(0, 3010, 1641)
  softwareName   = 'VNC *'
}
 
Install-ChocolateyInstallPackage @packageArgs

Remove-Item $extractDir -Recurse -Force | Out-Null
