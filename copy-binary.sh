#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INSTALLER_DIR="$ROOT_DIR/nebula-installer"
ISO_DIR="$ROOT_DIR/nebula-iso"
BIN_SRC="$INSTALLER_DIR/target/release/nebula"
BIN_DEST="$ISO_DIR/airootfs/usr/bin/nebula-installer"

cargo build --release --manifest-path "$INSTALLER_DIR/Cargo.toml"
install -Dm755 "$BIN_SRC" "$BIN_DEST"

echo "Updated live ISO binary at: $BIN_DEST"
