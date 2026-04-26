$ErrorActionPreference = 'Stop'

$packageName = $env:ChocolateyPackageName

$packageArgs = @{
    packageName    = $packageName
    softwareName   = 'NordVPN*'
    fileType       = 'exe'
    validExitCodes = @(0)
}

[array]$key = Get-UninstallRegistryKey -SoftwareName $packageArgs['softwareName']

if ($key.Count -eq 0) {
    Write-Warning "$packageName has already been uninstalled by other means."
} else {
    if ($key.Count -gt 1) {
        Write-Warning "$($key.Count) matches found for '$($packageArgs['softwareName'])'. Uninstalling all."
    }
    $key | ForEach-Object {
        # UninstallString may contain arguments after the exe path -- split them apart.
        # Quoted:   "C:\Program Files\NordVPN\unins000.exe" /somearg
        # Unquoted: C:\Program Files\NordVPN\unins000.exe
        $uninstallString = $_.UninstallString
        if ($uninstallString -match '^"([^"]+)"(.*)$') {
            $packageArgs['file'] = $Matches[1].Trim()
            $existingArgs        = $Matches[2].Trim()
        } else {
            $parts               = $uninstallString -split '\s+(?=/)', 2
            $packageArgs['file'] = $parts[0].Trim()
            $existingArgs        = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
        }

        # Merge any existing args with our silent flags, avoiding duplicates
        $packageArgs['silentArgs'] = (($existingArgs, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART') |
            Where-Object { $_ }) -join ' '

        Uninstall-ChocolateyPackage @packageArgs
    }
}