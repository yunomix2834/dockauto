#!/usr/bin/env bash
set -euo pipefail

dockauto_cmd_up_usage() {
  cat <<'EOF'
Usage: dockauto up [options]

Options:
  --keep-infra     Do not tear down infra when command exits (default: false)
  -p PORTSPEC      Port spec for checks (e.g. "8080:")
  -n NETWORK       Docker network name to check/use

Examples:
  dockauto up
  dockauto up --keep-infra
  dockauto up -p 8080: -n backend
EOF
}

dockauto_cmd_down_usage() {
  cat <<'EOF'
Usage: dockauto down

Stops dev infrastructure (containers, networks) created by dockauto up.
EOF
}

dockauto_cmd_up() {
  local keep_infra=0
  local port_spec=""      # e.g. "8080:"
  local network_name=""   # e.g. "backend"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep-infra)
        keep_infra=1
        shift
        ;;
      -p)
        port_spec="${2:-}"
        shift 2
        ;;
      -n)
        network_name="${2:-}"
        shift 2
        ;;
      -h|--help)
        dockauto_cmd_up_usage
        return 0
        ;;
      *)
        log_error "Unknown option for up: $1"
        dockauto_cmd_up_usage
        return 1
        ;;
    esac
  done

  log_debug "up: keep_infra=${keep_infra}"
  log_debug "up: port_spec=${port_spec}"
  log_debug "up: network_name=${network_name}"

  source "${DOCKAUTO_ROOT_DIR}/lib/config.sh"
  source "${DOCKAUTO_ROOT_DIR}/lib/validate.sh"

  # ====== Step 1 END ======

  # ====== Step 2 VALIDATE config + environment ======
  dockauto_config_load "${DOCKAUTO_CONFIG_FILE}" "${DOCKAUTO_PROFILE}"
  dockauto_validate_environment
  dockauto_validate_config

  log_info "Starting dev infra (up) (Step 7/9 not implemented yet)."
  log_info "Config file: ${DOCKAUTO_CONFIG_FILE}, profile: ${DOCKAUTO_PROFILE:-default}"

  if [[ -n "${port_spec}" ]]; then
    log_info "Will check port availability: ${port_spec} (TODO: implement in Step 7)."
  fi

  if [[ -n "${network_name}" ]]; then
    log_info "Will check/create network: ${network_name} (TODO: implement in Step 7)."
  fi

  if [[ "${keep_infra}" -eq 1 ]]; then
    log_info "Infra will be kept after up (no auto teardown)."
  fi

  # TODO Step 7: infra_up_dev + Step 9 (teardown) nếu không keep
}

dockauto_cmd_down() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        dockauto_cmd_down_usage
        return 0
        ;;
      *)
        log_error "Unknown option for down: $1"
        dockauto_cmd_down_usage
        return 1
        ;;
    esac
  done

  log_info "Stopping dev infra (Step 9 logic to be implemented)."
  # TODO: tìm containers/network theo naming convention (dockauto_dev_...) và stop/remove
}
