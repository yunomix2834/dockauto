#!/usr/bin/env bash
set -euo pipefail

# Install
VERSION="0.1.0"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="dockauto"

echo "Installing: ${BINARY_NAME} v${VERSION}..."

# Temp
TEMP_DIR="$(mktemp -d)"

# 1. Create Temp Folder
trap 'rm -rf "$TEMP_DIR"' EXIT

# 2. Download binary / script
curl -fsSL "https://raw.githubusercontent.com/yunomix2834/dockauto/v${VERSION}/bin/dockauto" -o "${TEMP_DIR}/${BINARY_NAME}"

# Grant execute mode to file
chmod +x "${TEMP_DIR}/${BINARY_NAME}"

# 3. Move to INSTALL_DIR
sudo mv "${TEMP_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"

echo "Installed ${BINARY_NAME} to ${INSTALL_DIR}/${BINARY_NAME}"
echo "Run: dockauto --version to view the version"