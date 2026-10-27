# https://www.realvnc.com/en/connect/download/viewer/
$ErrorActionPreference = 'Stop'
$packageName    = 'vnc-viewer'
$toolsDir       = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$extractDir     = "$toolsDir\extracted"
$url            = 'https://downloads.realvnc.com/download/file/realvnc-connect-viewer/RealVNC-Connect-Viewer-8.5.3-Windows.msi.zip'
$checksum       = '034c206f36ead3ce48d6a08f00796c16cdf818944c3b2027617221498b397479'
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
