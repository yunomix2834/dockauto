#!/usr/bin/env bash
set -euo pipefail

dockauto_scan_image() {
  local image_tag="$1"

  log_info "Scanning image ${image_tag} (Step 6 to be implemented)."
  # TODO: Trivy, SBOM, policy fail_on...
}
