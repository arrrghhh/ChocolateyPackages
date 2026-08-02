param(
    [switch]$Push
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\helpers.psm1" -Force

$PackageDirs = Get-ChildItem -Recurse . -Filter *.nuspec | Select-Object -ExpandProperty DirectoryName -Unique
Write-Log "Found $($PackageDirs.Count) packages to check" -Color Magenta

$Failures = @()

foreach ($Dir in $PackageDirs) {
    $PackageName = Split-Path $Dir -Leaf
    Write-Log "[Package: $PackageName]" -Color Cyan
    Write-Log "Location: $Dir"

    Push-Location $Dir
    try {
        if (Test-Path "update.ps1") {
            Write-Log "Dot-sourcing local update.ps1..." -Color Gray
            . ./update.ps1
        } else {
            if ($Push) { update -Push } else { update }
        }
    } catch {
        Write-Log "Failed to update ${PackageName}: $($_.Exception.Message)" -Color Red
        $Failures += [PSCustomObject]@{ Package = $PackageName; Error = $_.Exception.Message }
    } finally {
        Pop-Location
    }
}

Write-Log "All updates complete" -Color Magenta

if ($env:GITHUB_STEP_SUMMARY) {
    if ($Failures.Count -gt 0) {
        "## ⚠️ Package Update Failures ($($Failures.Count))" | Out-File $env:GITHUB_STEP_SUMMARY -Append
        "| Package | Error |" | Out-File $env:GITHUB_STEP_SUMMARY -Append
        "|---|---|" | Out-File $env:GITHUB_STEP_SUMMARY -Append
        foreach ($f in $Failures) {
            "| $($f.Package) | $($f.Error -replace '\|','\\|') |" | Out-File $env:GITHUB_STEP_SUMMARY -Append
        }
    } else {
        "## ✅ All packages updated successfully" | Out-File $env:GITHUB_STEP_SUMMARY -Append
    }
}

if ($Failures.Count -gt 0) {
    Write-Log "$($Failures.Count) package(s) failed: $($Failures.Package -join ', ')" -Color Red
    exit 1
}