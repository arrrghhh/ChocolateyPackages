$ErrorActionPreference = 'Stop'
import-module au

$ReleasePage = 'https://realvnc.com/en/connect/download/viewer/'

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

function global:au_SearchReplace {
	@{
		'tools/chocolateyInstall.ps1' = @{
			"(^[$]url\s*=\s*)('.*')"  = "`$1'$($Latest.URL32)'"
			"(^[$]checksum\s*=\s*)('.*')"     = "`$1'$($Latest.Checksum32)'"
			"(^[$]checksumType\s*=\s*)('.*')" = "`$1'$($Latest.ChecksumType32)'"
		}
	}
}

function global:au_GetLatest {
	Write-Host "Getting VNC Viewer MSI URL using Selenium..."
	Start-Sleep -Seconds 5
	$Option = Get-SeElement `
    			-By XPath `
    			-Value "//option[contains(@data-file,'-Windows-msi.zip')]"

	$URL32 = $Option.GetAttribute("data-file")
	
	# Parse version from URL
    $Version = ([uri]$URL32).Segments[-1].Split('-')[-3]
	
	Write-Host "Found latest version: $Version"
	Write-Host "Found URL: $URL32"

	$Latest = @{ URL32 = $URL32; Version = $Version }
	return $Latest
}

$Driver = Start-SeDriver `
    -Browser "firefox" `
    -State Headless `
    -StartURL $ReleasePage

update -ChecksumFor 32 -NoCheckUrl

$Driver.Quit()
$Driver.Dispose()