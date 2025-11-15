$ErrorActionPreference = 'Stop'

$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url        = 'https://download.filezilla-project.org/client/FileZilla_3.69.5_win32_sponsored2-setup.exe'
$url64      = 'https://download.filezilla-project.org/client/FileZilla_3.69.5_win64_sponsored2-setup.exe'

$packageArgs = @{
  packageName   = 'filezilla'
  fileType      = 'EXE'
  url           = $url
  url64bit      = $url64

  softwareName  = 'Filezilla 3*'

  checksum      = '9A29EA8D9C56B61CADE7EC3CCF1C26CCC6466619867926DD655F13C8027ED8C5'
  checksumType  = 'sha256'
  checksum64    = '77BD820EB0532CFC5AD6523E6ABE7C287D2C53AE1C9B8DDC156706F32092D03B'
  checksumType64= 'sha256'

  silentArgs    = "/S"
  validExitCodes= @(0, 1223)
}

Install-ChocolateyPackage @packageArgs