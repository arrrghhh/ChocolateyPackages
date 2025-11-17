$ErrorActionPreference = 'Stop'

$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

$packageArgs = @{
  packageName   = 'filezilla'
  fileType      = 'EXE'
  file          = Get-Item $toolsDir\*_win32-setup.exe
  file64        = Get-Item $toolsDir\*_win64-setup.exe
  softwareName  = 'Filezilla 3*'
  silentArgs    = "/S"
  validExitCodes= @(0, 1223)
}

Install-ChocolateyInstallPackage @packageArgs
Get-ChildItem $toolsDir\*.exe | ForEach-Object { Remove-Item $_ -ea 0; if (Test-Path $_) { Set-Content -Value "" -Path "$_.ignore" }}