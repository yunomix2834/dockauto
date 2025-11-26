#!/usr/bin/env bash
set -euo pipefail

# dockauto up/down:
#   Step 1: parse flags
#   Step 2: VALIDATE config + environment
#   Step 7/9: infra up / teardown (future)

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
  # ====== Step 1: Parse flags ======
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

  # up not related to test/scan -> set context default
  export DOCKAUTO_REQUIRE_INFRA="0"
  export DOCKAUTO_SKIP_TEST="1"
  export DOCKAUTO_NO_SCAN="1"

  # ====== Step 2 VALIDATE config + environment ======
  source "${DOCKAUTO_ROOT_DIR}/lib/config.sh"
  source "${DOCKAUTO_ROOT_DIR}/lib/validate.sh"

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

  # TODO Step 7:
  #   - create networks/containers for infra services (role=infra)
  #   - healthcheck loop
  #   - handle naming: dockauto_dev_<service>
}

dockauto_cmd_down() {
  # ====== Step 1: Parse flags ======
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

  # Step 9 (future)
  log_info "Stopping dev infra (Step 9 logic to be implemented)."
  # TODO:
  #   - stop/remove containers/network with naming pattern dockauto_dev_*
}
