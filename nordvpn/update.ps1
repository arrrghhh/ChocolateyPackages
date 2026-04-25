# NordVPN - Chocolatey AU update script
#
# Version detection: queries the Microsoft winget-pkgs GitHub repo, which tracks
# NordVPN releases reliably (typically within a day or two of each release).
# This avoids nordvpn.com's Cloudflare bot protection and avoids downloading
# the full 80MB installer just to check a version number.
#
# Versioned installer URL format:
#   https://downloads.nordcdn.com/apps/windows/NordVPN/{VERSION}/NordVPNInstall.exe

$ErrorActionPreference = 'Stop'

$wingetManifestUrl = 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/n/NordSecurity/NordVPN'

function global:au_GetLatest {
    # GitHub API returns a list of version directories; pick the highest
    $versions = Invoke-RestMethod -Uri $wingetManifestUrl -UseBasicParsing
    $version = $versions |
        Where-Object { $_.type -eq 'dir' } |
        Select-Object -ExpandProperty name |
        Sort-Object { [version]$_ } |
        Select-Object -Last 1

    if (-not $version) { throw "Could not determine latest NordVPN version from winget-pkgs" }

    $url = "https://downloads.nordcdn.com/apps/windows/NordVPN/$version/NordVPNInstall.exe"

    return @{
        Version = $version
        URL32   = $url
    }
}

function global:au_SearchReplace {
    @{
        "tools\chocolateyInstall.ps1" = @{
            "(^\s*url\s*=\s*)'.*'"         = "`$1'$($Latest.URL32)'"
            "(^\s*checksum\s*=\s*)'.*'"    = "`$1'$($Latest.Checksum32)'"
            "(^\s*checksumType\s*=\s*)'.*'" = "`$1'$($Latest.ChecksumType32)'"
        }
        "nordvpn.nuspec" = @{
            "(<version>)[^<]*(</version>)" = "`${1}$($Latest.Version)`${2}"
        }
    }
}

update