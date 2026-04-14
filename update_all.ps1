param(
    [switch]$Push
)

$ErrorActionPreference = 'Stop'

# Import shared helpers (Write-Log, etc.)
Import-Module "$PSScriptRoot\helpers.psm1" -Force

# Get all directories containing a nuspec file
$PackageDirs = Get-ChildItem -Recurse . -Filter *.nuspec | Select-Object -ExpandProperty DirectoryName -Unique

Write-Log "Found $($PackageDirs.Count) packages to check" -Color Magenta

foreach ($Dir in $PackageDirs) {
    $PackageName = Split-Path $Dir -Leaf
    Write-Log "[Package: $PackageName]" -Color Cyan
    Write-Log "Location: $Dir"

    Push-Location $Dir

    try {
        if (Test-Path "update.ps1") {
            Write-Log "Dot-sourcing local update.ps1..." -Color Gray
            if ($Push) { . ./update.ps1 -Push } else { . ./update.ps1 }
        } else {
            if ($Push) { update -Push } else { update }
        }
    } catch {
        Write-Log "Failed to update ${PackageName}: $($_.Exception.Message)" -Color Red
    } finally {
        Pop-Location
    }
}

Write-Log "All updates complete" -Color Magenta