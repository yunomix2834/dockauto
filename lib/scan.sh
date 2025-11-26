#!/usr/bin/env bash
set -euo pipefail

# ====== Step 6: Scan image (Trivy / SBOM) ======

dockauto_scan_image() {
  local image_tag="$1"

  if [[ "${DOCKAUTO_SCAN_AVAILABLE:-1}" -ne 1 ]]; then
    log_warn "Scan tools not available or --no-scan enabled; skipping scan for image ${image_tag}."
    return 0
  fi

  log_info "Scanning image ${image_tag} (Step 6 to be implemented)."
  log_info "Scan tool: ${DOCKAUTO_CFG_SECURITY_SCAN_TOOL}, SBOM tool: ${DOCKAUTO_CFG_SECURITY_SBOM_TOOL}"
  # TODO:
  #   - trivy image ...
  #   - syft packages ...
  #   - apply fail_on policy
}
