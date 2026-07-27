#!/bin/sh

set -eu

INSTALL_ROOT="${HPDOS_INSTALL_ROOT:-$HOME/.local/share/hpdos}"
BIN_DIR="${HPDOS_BIN_DIR:-$HOME/.local/bin}"

rm_file_if_managed() {
  path="$1"
  if [ -f "$path" ] && grep -F "$INSTALL_ROOT/current/hpdos" "$path" >/dev/null 2>&1; then
    rm -f "$path"
  fi
}

rm_file_if_managed "$BIN_DIR/hpdos"

if [ -d "$INSTALL_ROOT" ]; then
  rm -rf "$INSTALL_ROOT/versions" "$INSTALL_ROOT/current"
fi

printf 'HPDOS program files were removed.\n'
printf 'Backend service state and user data were preserved.\n'
