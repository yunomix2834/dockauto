#!/usr/bin/env bash
set -euo pipefail

# Config
readonly DOCKAUTO_VERSION="${DOCKAUTO_VERSION:-0.1.0}"
readonly INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
readonly BINARY_NAME="dockauto"

echo "Installing: ${BINARY_NAME} v${DOCKAUTO_VERSION} -> ${INSTALL_DIR}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required. Please install curl first." >&2
  exit 1
fi

if [[ ! -w "${INSTALL_DIR}" ]]; then
  echo "WARN: ${INSTALL_DIR} is not writable, will use sudo to move binary." >&2
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

URL="https://raw.githubusercontent.com/yunomix2834/dockauto/v${DOCKAUTO_VERSION}/bin/dockauto"
echo "Downloading from: ${URL}"

curl -fsSL "$URL" -o "${TEMP_DIR}/${BINARY_NAME}"
chmod +x "${TEMP_DIR}/${BINARY_NAME}"

# Use sudo only if needed
if mv "${TEMP_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}" 2>/dev/null; then
  :
else
  sudo mv "${TEMP_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
fi

echo "Installed ${BINARY_NAME} -> ${INSTALL_DIR}/${BINARY_NAME}"
echo "Run: dockauto --version"
