#!/usr/bin/env bash
set -euo pipefail

dockauto_validate_environment() {
  log_debug "Validating environment (docker, yq, jq, trivy, ...)"

  # TODO Step 2: check command -v docker/yq/jq/trivy/syft...
  # ví dụ:
  # command -v docker >/dev/null || { log_error "docker not found"; exit 1; }
}

dockauto_validate_config() {
  log_debug "Validating config structure in ${DOCKAUTO_CONFIG_FILE}"

  # TODO Step 2: validate language, main_service, tests, infra...
}
