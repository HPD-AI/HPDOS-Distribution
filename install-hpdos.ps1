param(
    [string]$Version = $env:HPDOS_VERSION,
    [string]$Repository = $(if ($env:HPDOS_REPOSITORY) { $env:HPDOS_REPOSITORY } else { "HPD-AI/HPDOS-Distribution" }),
    [string]$InstallRoot = $(if ($env:HPDOS_INSTALL_ROOT) { $env:HPDOS_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "HPDOS" }),
    [string]$BinDirectory = $(if ($env:HPDOS_BIN_DIR) { $env:HPDOS_BIN_DIR } else { Join-Path $env:LOCALAPPDATA "HPDOS\\bin" })
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

$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
$rid = switch ($architecture) {
    "X64" { "win-x64" }
    "Arm64" { "win-arm64" }
    default { throw "Unsupported Windows architecture: $architecture" }
}

if (-not $Version) {
    $latest = Invoke-RestMethod -Headers @{ "User-Agent" = "hpdos-installer" } `
        -Uri "https://api.github.com/repos/$Repository/releases/latest"
    if ($latest.tag_name -notlike "hpdos-v*") { throw "No HPDOS release is available." }
    $Version = Normalize-Version $latest.tag_name
} else {
    $Version = Normalize-Version $Version
}

$tag = "hpdos-v$Version"
$asset = "hpdos-$rid.zip"
$base = "https://github.com/$Repository/releases/download/$tag"
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ("hpdos-install-" + [Guid]::NewGuid().ToString("N"))
$archive = Join-Path $temporary $asset
$checksums = Join-Path $temporary "SHA256SUMS"

try {
    New-Item -ItemType Directory -Force -Path $temporary | Out-Null
    Invoke-WebRequest -Headers @{ "User-Agent" = "hpdos-installer" } -Uri "$base/$asset" -OutFile $archive
    Invoke-WebRequest -Headers @{ "User-Agent" = "hpdos-installer" } -Uri "$base/SHA256SUMS" -OutFile $checksums

    $checksumLine = Get-Content $checksums | Where-Object { $_ -match "(^|[ *])$([regex]::Escape($asset))$" } | Select-Object -First 1
    if (-not $checksumLine) { throw "$asset is absent from SHA256SUMS." }
    $expected = ($checksumLine -split '\s+')[0].ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Checksum mismatch." }

    $versions = Join-Path $InstallRoot "versions"
    $staging = Join-Path $versions (".staging-$Version-" + [Guid]::NewGuid().ToString("N"))
    $target = Join-Path $versions $Version
    New-Item -ItemType Directory -Force -Path $staging, $BinDirectory | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $staging

    foreach ($required in @("hpdos.exe", "backend\\hpdos-backend.exe", "release.json")) {
        if (-not (Test-Path -LiteralPath (Join-Path $staging $required))) {
            throw "The release archive is missing $required."
        }
    }

    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    } else {
        Move-Item -LiteralPath $staging -Destination $target
    }

    $currentFile = Join-Path $InstallRoot "current.txt"
    $temporaryCurrent = "$currentFile.tmp"
    Set-Content -LiteralPath $temporaryCurrent -Value $target -NoNewline
    Move-Item -LiteralPath $temporaryCurrent -Destination $currentFile -Force

    $launcher = Join-Path $BinDirectory "hpdos.cmd"
    $temporaryLauncher = "$launcher.tmp"
    Set-Content -LiteralPath $temporaryLauncher -Value "@echo off`r`n`"$target\\hpdos.exe`" %*`r`n" -NoNewline
    Move-Item -LiteralPath $temporaryLauncher -Destination $launcher -Force

    Write-Host "HPDOS $Version installed. Run: $launcher"
} finally {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Recurse -Force
    }
}
