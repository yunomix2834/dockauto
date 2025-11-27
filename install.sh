#!/usr/bin/env bash
set -euo pipefail

# Config
readonly REPO_OWNER="yunomix2834"
readonly REPO_NAME="dockauto"

readonly DOCKAUTO_VERSION="${DOCKAUTO_VERSION:-0.1.0}"
readonly INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
readonly LIB_DIR="${LIB_DIR:-/usr/local/lib/dockauto}"

readonly BINARY_NAME="dockauto"

echo "Installing: ${BINARY_NAME} v${DOCKAUTO_VERSION} -> ${INSTALL_DIR}"
echo "  BIN  -> ${INSTALL_DIR}/${BINARY_NAME}"
echo "  LIBS -> ${LIB_DIR}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required. Please install curl first." >&2
  exit 1
fi

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
  linux|darwin)
    ;;
  *)
    echo "ERROR: Unsupported OS: ${OS}. Only Linux and macOS are supported for now." >&2
    exit 1
    ;;
esac

# Ensure install dirs
ensure_dir() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    echo "Creating directory: ${dir}"
    if mkdir -p "${dir}" 2>/dev/null; then
      :
    elif command -v sudo >/dev/null 2>&1 && sudo mkdir -p "${dir}" 2>/dev/null; then
      :
    else
      echo "ERROR: Cannot create ${dir} (even with sudo)." >&2
      exit 1
    fi
  fi
}

ensure_dir "${INSTALL_DIR}"
ensure_dir "${LIB_DIR}"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Download source tarball for this version
TARBALL_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/tags/v${DOCKAUTO_VERSION}.tar.gz"
echo "Downloading source tarball: ${TARBALL_URL}"

if ! curl -fsSL "$TARBALL_URL" -o "${TEMP_DIR}/src.tar.gz"; then
  echo "ERROR: Failed to download tarball for v${DOCKAUTO_VERSION}." >&2
  exit 1
fi

echo "Extracting..."
tar -xzf "${TEMP_DIR}/src.tar.gz" -C "${TEMP_DIR}"

SRC_ROOT="$(find "${TEMP_DIR}" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n1)"

if [[ -z "${SRC_ROOT}" || ! -d "${SRC_ROOT}" ]]; then
  echo "ERROR: Cannot find extracted source directory." >&2
  exit 1
fi

# Copy lib & templates vào LIB_DIR
echo "Installing libraries to ${LIB_DIR} ..."
if cp -R "${SRC_ROOT}/lib" "${SRC_ROOT}/templates" "${LIB_DIR}" 2>/dev/null; then
  :
elif command -v sudo >/dev/null 2>&1 && sudo cp -R "${SRC_ROOT}/lib" "${SRC_ROOT}/templates" "${LIB_DIR}"; then
  :
else
  echo "ERROR: Cannot copy lib/templates to ${LIB_DIR}, even with sudo." >&2
  exit 1
fi

# Copy binary
BIN_SRC="${SRC_ROOT}/bin/${BINARY_NAME}"
if [[ ! -f "${BIN_SRC}" ]]; then
  echo "ERROR: Binary script not found at ${BIN_SRC} in tarball." >&2
  exit 1
fi

chmod +x "${BIN_SRC}"

echo "Installing binary to ${INSTALL_DIR}/${BINARY_NAME} ..."
if cp "${BIN_SRC}" "${INSTALL_DIR}/${BINARY_NAME}" 2>/dev/null; then
  :
elif command -v sudo >/dev/null 2>&1 && sudo cp "${BIN_SRC}" "${INSTALL_DIR}/${BINARY_NAME}"; then
  :
else
  echo "ERROR: Cannot install binary to ${INSTALL_DIR}, even with sudo." >&2
  exit 1
fi

echo "Installed ${BINARY_NAME} v${DOCKAUTO_VERSION}"
echo "  Binary : ${INSTALL_DIR}/${BINARY_NAME}"
echo "  LibDir : ${LIB_DIR}"
echo
echo "Run: dockauto --version"