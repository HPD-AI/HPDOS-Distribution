param(
    [string]$Version = $env:HPDOS_VERSION,

    [string]$Repository = $(
        if ($env:HPDOS_REPOSITORY) {
            $env:HPDOS_REPOSITORY
        } else {
            "HPD-AI/HPDOS-Distribution"
        }
    ),

    [string]$InstallRoot = $(
        if ($env:HPDOS_INSTALL_ROOT) {
            $env:HPDOS_INSTALL_ROOT
        } else {
            Join-Path $env:LOCALAPPDATA "HPDOS"
        }
    ),

    [string]$BinDirectory = $(
        if ($env:HPDOS_BIN_DIR) {
            $env:HPDOS_BIN_DIR
        } else {
            Join-Path $env:LOCALAPPDATA "HPDOS\bin"
        }
    )
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Normalize-Version([string]$Value) {
    $normalized = $Value -replace '^(hpdos-v|v)', ''

    if ($normalized -notmatch '^[0-9A-Za-z.+-]+$') {
        throw "Invalid HPDOS version."
    }

    return $normalized
}

# -------------------------------------------------------------------------
# Detect Windows architecture without RuntimeInformation.
#
# PROCESSOR_ARCHITEW6432 is populated when a 32-bit process is running on
# 64-bit Windows, so check it before PROCESSOR_ARCHITECTURE.
# -------------------------------------------------------------------------

$processArchitecture = $env:PROCESSOR_ARCHITECTURE
$wowArchitecture = $env:PROCESSOR_ARCHITEW6432

if (
    $processArchitecture -eq "ARM64" -or
    $wowArchitecture -eq "ARM64"
) {
    $rid = "win-arm64"
}
elseif (
    $processArchitecture -eq "AMD64" -or
    $wowArchitecture -eq "AMD64"
) {
    $rid = "win-x64"
}
else {
    throw "Unsupported Windows architecture: PROCESSOR_ARCHITECTURE=$processArchitecture, PROCESSOR_ARCHITEW6432=$wowArchitecture"
}

# -------------------------------------------------------------------------
# Determine version.
# -------------------------------------------------------------------------

if (-not $Version) {
    $latest = Invoke-RestMethod `
        -Headers @{ "User-Agent" = "hpdos-installer" } `
        -Uri "https://api.github.com/repos/$Repository/releases/latest"

    if ($latest.tag_name -notlike "hpdos-v*") {
        throw "No HPDOS release is available."
    }

    $Version = Normalize-Version $latest.tag_name
}
else {
    $Version = Normalize-Version $Version
}

$tag = "hpdos-v$Version"
$asset = "hpdos-$rid.zip"
$base = "https://github.com/$Repository/releases/download/$tag"

$temporary = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    ("hpdos-install-" + [Guid]::NewGuid().ToString("N"))

$archive = Join-Path $temporary $asset
$checksums = Join-Path $temporary "SHA256SUMS"

try {
    # ---------------------------------------------------------------------
    # Download
    # ---------------------------------------------------------------------

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $temporary |
        Out-Null

    Write-Host "Downloading HPDOS $Version for $rid..."

    Invoke-WebRequest `
        -Headers @{ "User-Agent" = "hpdos-installer" } `
        -Uri "$base/$asset" `
        -OutFile $archive

    Invoke-WebRequest `
        -Headers @{ "User-Agent" = "hpdos-installer" } `
        -Uri "$base/SHA256SUMS" `
        -OutFile $checksums

    # ---------------------------------------------------------------------
    # Verify checksum
    # ---------------------------------------------------------------------

    $checksumLine = Get-Content $checksums |
        Where-Object {
            $_ -match "(^|[ *])$([regex]::Escape($asset))$"
        } |
        Select-Object -First 1

    if (-not $checksumLine) {
        throw "$asset is absent from SHA256SUMS."
    }

    # IMPORTANT: \s+ is intentional.
    $expected = ($checksumLine -split '\s+')[0].ToLowerInvariant()

    $actual = (
        Get-FileHash `
            -Algorithm SHA256 `
            -LiteralPath $archive
    ).Hash.ToLowerInvariant()

    if ($actual -ne $expected) {
        throw "Checksum mismatch."
    }

    Write-Host "[OK] Download checksum verified."

    # ---------------------------------------------------------------------
    # Prepare installation directories
    # ---------------------------------------------------------------------

    $versions = Join-Path $InstallRoot "versions"

    $staging = Join-Path `
        $versions `
        (".staging-$Version-" + [Guid]::NewGuid().ToString("N"))

    $target = Join-Path $versions $Version

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $staging |
        Out-Null

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $BinDirectory |
        Out-Null

    # ---------------------------------------------------------------------
    # Extract release
    # ---------------------------------------------------------------------

    Write-Host "Installing HPDOS $Version..."

    Expand-Archive `
        -LiteralPath $archive `
        -DestinationPath $staging

    # ---------------------------------------------------------------------
    # Validate release contents
    # ---------------------------------------------------------------------

    foreach ($required in @(
        "hpdos.exe",
        "backend\hpdos-backend.exe",
        "release.json"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $staging $required))) {
            throw "The release archive is missing $required."
        }
    }

    # ---------------------------------------------------------------------
    # Install version
    # ---------------------------------------------------------------------

    if (Test-Path -LiteralPath $target) {
        Write-Host "Version $Version is already installed."

        Remove-Item `
            -LiteralPath $staging `
            -Recurse `
            -Force
    }
    else {
        Move-Item `
            -LiteralPath $staging `
            -Destination $target
    }

    # ---------------------------------------------------------------------
    # Update current version pointer
    # ---------------------------------------------------------------------

    $currentFile = Join-Path $InstallRoot "current.txt"
    $temporaryCurrent = "$currentFile.tmp"

    Set-Content `
        -LiteralPath $temporaryCurrent `
        -Value $target `
        -NoNewline

    Move-Item `
        -LiteralPath $temporaryCurrent `
        -Destination $currentFile `
        -Force

    # ---------------------------------------------------------------------
    # Create launcher
    # ---------------------------------------------------------------------

    $launcher = Join-Path $BinDirectory "hpdos.cmd"
    $temporaryLauncher = "$launcher.tmp"

    $launcherContent = "@echo off`r`n`"$target\hpdos.exe`" %*`r`n"

    Set-Content `
        -LiteralPath $temporaryLauncher `
        -Value $launcherContent `
        -NoNewline

    Move-Item `
        -LiteralPath $temporaryLauncher `
        -Destination $launcher `
        -Force

    # ---------------------------------------------------------------------
    # Configure persistent user PATH
    # ---------------------------------------------------------------------

    Write-Host ""
    Write-Host "HPDOS $Version installed."
    Write-Host "Launcher: $launcher"

    $normalizedBin = $BinDirectory.TrimEnd('\')

    $userPath = [Environment]::GetEnvironmentVariable(
        "Path",
        "User"
    )

    $userPathEntries = @()

    if ($userPath) {
        $userPathEntries = $userPath -split ';' |
            Where-Object {
                $_ -and $_.Trim()
            }
    }

    $persistentPathMatch = $userPathEntries |
        Where-Object {
            [string]::Equals(
                $_.TrimEnd('\'),
                $normalizedBin,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }

    if (-not $persistentPathMatch) {
        if ($userPath) {
            $newUserPath = "$normalizedBin;$userPath"
        }
        else {
            $newUserPath = $normalizedBin
        }

        [Environment]::SetEnvironmentVariable(
            "Path",
            $newUserPath,
            "User"
        )

        Write-Host "[OK] Added $normalizedBin to your user PATH."
    }
    else {
        Write-Host "[OK] $normalizedBin is already in your user PATH."
    }

    # ---------------------------------------------------------------------
    # Update the current PowerShell process PATH.
    #
    # This works when the installer is executed directly in the current
    # PowerShell process, including:
    #
    #   irm ... | iex
    #
    # It cannot modify the environment of a parent PowerShell process when
    # this script is launched through a separate powershell.exe process.
    # ---------------------------------------------------------------------

    $currentPathEntries = $env:Path -split ';'

    $currentPathMatch = $currentPathEntries |
        Where-Object {
            $_ -and [string]::Equals(
                $_.TrimEnd('\'),
                $normalizedBin,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }

    if (-not $currentPathMatch) {
        $env:Path = "$normalizedBin;$env:Path"
    }

    # ---------------------------------------------------------------------
    # Verify launcher
    # ---------------------------------------------------------------------

    Write-Host ""

    if (-not (Test-Path -LiteralPath $launcher)) {
        throw "HPDOS launcher was not created: $launcher"
    }

    try {
        $command = Get-Command hpdos -ErrorAction Stop

        Write-Host "[OK] Verified: hpdos command is available."
        Write-Host "     Command: $($command.Source)"
        Write-Host ""
        Write-Host "HPDOS is ready."
        Write-Host ""
        Write-Host "Run:"
        Write-Host "  hpdos"
        Write-Host ""
        Write-Host "Other useful commands:"
        Write-Host "  hpdos doctor"
        Write-Host "  hpdos backend"
        Write-Host "  hpdos service status"
    }
    catch {
        Write-Warning "HPDOS was installed, but this PowerShell session cannot find 'hpdos'."

        Write-Host ""
        Write-Host "Run this command in the current PowerShell session:"
        Write-Host ""
        Write-Host "  `$env:Path = `"$normalizedBin;`$env:Path`""
        Write-Host ""
        Write-Host "Then run:"
        Write-Host ""
        Write-Host "  hpdos"
        Write-Host ""
        Write-Host "New PowerShell windows will automatically have 'hpdos' available."
    }

}
finally {
    # ---------------------------------------------------------------------
    # Cleanup
    # ---------------------------------------------------------------------

    if (Test-Path -LiteralPath $temporary) {
        Remove-Item `
            -LiteralPath $temporary `
            -Recurse `
            -Force
    }
}
