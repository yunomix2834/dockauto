#!/usr/bin/env bash
set -euo pipefail

# ====== Step 0: dockauto wrapper ======

# dockauto version
VERSION="0.1.0"

# Find project's root folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Export for lib to use
export DOCKAUTO_ROOT_DIR="${ROOT_DIR}"
export DOCKAUTO_VERSION="${VERSION}"

# Source for primary lib
# At least we need cli & utils for Step 1+
source "${ROOT_DIR}/lib/utils.sh"
source "${ROOT_DIR}/lib/cli.sh"

dockauto_main "$@"