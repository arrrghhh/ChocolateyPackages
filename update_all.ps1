# This goes in the ROOT of your repo
param(
    [switch]$Push
)
$ErrorActionPreference = 'Stop'

# Ensure AU is available
if (-not (Get-Module -ListAvailable au)) {
    Write-Host "Installing AU module..." -ForegroundColor Cyan
    Install-Module au -Force -Scope CurrentUser -AllowClobber
}
Import-Module au

# Get all directories containing a nuspec file
$PackageDirs = Get-ChildItem -Recurse . -Filter *.nuspec | Select-Object -ExpandProperty DirectoryName -Unique

Write-Host "--- Found $($PackageDirs.Count) packages to check ---" -ForegroundColor Magenta

foreach ($Dir in $PackageDirs) {
    $PackageName = Split-Path $Dir -Leaf
    Write-Host "`n[Package: $PackageName]" -ForegroundColor Cyan
    Write-Host "Location: $Dir"
    
    Push-Location $Dir
    try {
        # Check if a local update.ps1 exists; if so, dot-source it so functions are in scope
        if (Test-Path "update.ps1") {
            Write-Host "Dot-sourcing local update.ps1..." -ForegroundColor Gray
            # Using dot-sourcing ensures the au_GetLatest functions are available to the 'update' command
            . ./update.ps1
            if ($Push) { update -Push }
        } else {
            # Standard AU update if no custom script is present
            if ($Push) { update -Push } else { update }
        }
    } catch {
        # Fixed: Using ${} to delimit the variable name from the following colon
        Write-Host "Failed to update ${PackageName}: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        Pop-Location
    }
}

Write-Host "`n--- All updates complete ---" -ForegroundColor Magenta
