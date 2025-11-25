#!/usr/bin/env bash
set -euo pipefail

dockauto_cmd_test_usage() {
  cat <<'EOF'
Usage: dockauto test [options]

Options:
  --infra                  Require infra (db/broker) for tests
  --ignore-test-failure    Do not fail if tests fail (just warn)
  --test SUITES            Comma-separated test suites (e.g. "unit,integration")

Examples:
  dockauto test
  dockauto test --test integration
  dockauto test --infra --test unit,integration
EOF
}

dockauto_cmd_test() {
  local require_infra=0
  local ignore_test_failure=0
  local test_suites=""   # "unit,integration"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --infra)
        require_infra=1
        shift
        ;;
      --ignore-test-failure)
        ignore_test_failure=1
        shift
        ;;
      --test|--tests)
        test_suites="${2:-}"
        shift 2
        ;;
      -h|--help)
        dockauto_cmd_test_usage
        return 0
        ;;
      *)
        log_error "Unknown option for test: $1"
        dockauto_cmd_test_usage
        return 1
        ;;
    esac
  done

  log_debug "test: require_infra=${require_infra}"
  log_debug "test: ignore_test_failure=${ignore_test_failure}"
  log_debug "test: test_suites=${test_suites}"

  # ====== Step 1 END ======

  # ====== Step 2 VALIDATE config + environment ======
  source "${DOCKAUTO_ROOT_DIR}/lib/config.sh"
  source "${DOCKAUTO_ROOT_DIR}/lib/validate.sh"

  dockauto_config_load "${DOCKAUTO_CONFIG_FILE}" "${DOCKAUTO_PROFILE}"
  dockauto_validate_environment
  dockauto_validate_config

  log_info "Starting test pipeline (Step 2+ not implemented yet)."
  log_info "Config file: ${DOCKAUTO_CONFIG_FILE}, profile: ${DOCKAUTO_PROFILE:-default}"

  if [[ "${require_infra}" -eq 1 ]]; then
    log_info "Infra (db/broker) will be required for tests."
  fi

  if [[ "${ignore_test_failure}" -eq 1 ]]; then
    log_info "Test failures will not fail the command (ignore-test-failure)."
  fi

  # TODO: Step 7,8: infra_up + run_tests + (optional) cleanup
}
