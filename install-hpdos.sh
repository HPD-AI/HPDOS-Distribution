#!/bin/sh

set -eu

REPOSITORY="${HPDOS_REPOSITORY:-HPD-AI/HPDOS-Distribution}"
INSTALL_ROOT="${HPDOS_INSTALL_ROOT:-$HOME/.local/share/hpdos}"
BIN_DIR="${HPDOS_BIN_DIR:-$HOME/.local/bin}"
REQUESTED_VERSION="${HPDOS_VERSION:-}"
TEMP_DIR=""

fail() {
  printf 'HPDOS installation failed: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}

trap cleanup EXIT HUP INT TERM

download() {
  url="$1"
  output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -H "User-Agent: hpdos-installer" "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --user-agent="hpdos-installer" -O "$output" "$url"
  else
    fail "curl or wget is required."
  fi
}

sha256() {
  path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" | sed 's/^.*= //'
  else
    fail "sha256sum, shasum, or openssl is required."
  fi
}

rid() {
  case "$(uname -s 2>/dev/null):$(uname -m 2>/dev/null)" in
    Darwin:arm64) printf 'osx-arm64\n' ;;
    Darwin:x86_64) printf 'osx-x64\n' ;;
    Linux:aarch64|Linux:arm64) printf 'linux-arm64\n' ;;
    Linux:x86_64|Linux:amd64) printf 'linux-x64\n' ;;
    *) fail "This platform is not supported." ;;
  esac
}

normalize_version() {
  value="$1"
  value=${value#hpdos-v}
  value=${value#v}
  case "$value" in
    ''|*[!0-9A-Za-z.+-]*) fail "Invalid version." ;;
  esac
  printf '%s\n' "$value"
}

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hpdos-install.XXXXXX")

if [ -z "$REQUESTED_VERSION" ]; then
  latest="$TEMP_DIR/latest.json"
  download "https://api.github.com/repos/$REPOSITORY/releases/latest" "$latest" || fail "No HPDOS release is available."
  tag=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\(hpdos-v[^"]*\)".*/\1/p' "$latest" | head -n 1)
  [ -n "$tag" ] || fail "No HPDOS release is available."
  VERSION=$(normalize_version "$tag")
else
  VERSION=$(normalize_version "$REQUESTED_VERSION")
fi

RID=$(rid)
TAG="hpdos-v$VERSION"
ASSET="hpdos-$RID.tar.gz"
BASE="https://github.com/$REPOSITORY/releases/download/$TAG"
ARCHIVE="$TEMP_DIR/$ASSET"
CHECKSUMS="$TEMP_DIR/SHA256SUMS"

printf 'Installing HPDOS %s for %s...\n' "$VERSION" "$RID"
download "$BASE/$ASSET" "$ARCHIVE"
download "$BASE/SHA256SUMS" "$CHECKSUMS"

EXPECTED=$(awk -v asset="$ASSET" '$2 == asset || $2 == "*" asset { print $1; exit }' "$CHECKSUMS")
[ -n "$EXPECTED" ] || fail "$ASSET is absent from SHA256SUMS."
[ "$(sha256 "$ARCHIVE")" = "$EXPECTED" ] || fail "Checksum mismatch."

VERSIONS="$INSTALL_ROOT/versions"
STAGING="$VERSIONS/.staging-$VERSION-$$"
TARGET="$VERSIONS/$VERSION"
mkdir -p "$STAGING" "$BIN_DIR"
tar -xzf "$ARCHIVE" -C "$STAGING"
[ -x "$STAGING/hpdos" ] || fail "The archive has no executable hpdos."
[ -x "$STAGING/backend/hpdos-backend" ] || fail "The archive has no backend executable."
[ -f "$STAGING/release.json" ] || fail "The archive has no release.json."

if [ -e "$TARGET" ]; then
  rm -rf "$STAGING"
else
  mv "$STAGING" "$TARGET"
fi
ln -sfn "versions/$VERSION" "$INSTALL_ROOT/current"

LAUNCHER="$BIN_DIR/hpdos"
temporary_launcher="$BIN_DIR/.hpdos-launcher-$$"
printf '#!/bin/sh\nexec "%s/current/hpdos" "$@"\n' "$INSTALL_ROOT" > "$temporary_launcher"
chmod +x "$temporary_launcher"
mv "$temporary_launcher" "$LAUNCHER"

printf 'HPDOS %s installed. Run: %s\n' "$VERSION" "$LAUNCHER"
