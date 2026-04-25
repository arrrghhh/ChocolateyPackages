$ErrorActionPreference = 'Stop'

$packageName = $env:ChocolateyPackageName

$packageArgs = @{
    packageName    = $packageName
    softwareName   = 'NordVPN*'
    fileType       = 'exe'
    # InnoSetup uninstall switches
    silentArgs     = '/SILENT /SUPPRESSMSGBOXES /NORESTART'
    validExitCodes = @(0)
}

[array]$key = Get-UninstallRegistryKey -SoftwareName $packageArgs['softwareName']

if ($key.Count -eq 1) {
    $key | ForEach-Object {
        # InnoSetup uninstallers are standalone EXEs
        $packageArgs['file'] = "$($_.UninstallString)" -replace '"', ''
        Uninstall-ChocolateyPackage @packageArgs
    }
} elseif ($key.Count -eq 0) {
    Write-Warning "$packageName has already been uninstalled by other means."
} elseif ($key.Count -gt 1) {
    Write-Warning "$($key.Count) matches found for '$($packageArgs['softwareName'])'. Uninstalling all."
    $key | ForEach-Object {
        $packageArgs['file'] = "$($_.UninstallString)" -replace '"', ''
        Uninstall-ChocolateyPackage @packageArgs
    }
}
