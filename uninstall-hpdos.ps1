param(
    [string]$InstallRoot = $(if ($env:HPDOS_INSTALL_ROOT) { $env:HPDOS_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "HPDOS" }),
    [string]$BinDirectory = $(if ($env:HPDOS_BIN_DIR) { $env:HPDOS_BIN_DIR } else { Join-Path $env:LOCALAPPDATA "HPDOS\\bin" })
)

$ErrorActionPreference = "Stop"

$launcher = Join-Path $BinDirectory "hpdos.cmd"
if (Test-Path -LiteralPath $launcher) {
    $contents = Get-Content -LiteralPath $launcher -Raw
    if ($contents.Contains($InstallRoot)) {
        Remove-Item -LiteralPath $launcher -Force
    }
}

foreach ($path in @((Join-Path $InstallRoot "versions"), (Join-Path $InstallRoot "current.txt"))) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

Write-Host "HPDOS program files were removed."
Write-Host "Backend service state and user data were preserved."
