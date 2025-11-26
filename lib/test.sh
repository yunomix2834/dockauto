#!/usr/bin/env bash
set -euo pipefail

# dockauto test:
#   Step 1: parse test flags
#   Step 2: VALIDATE config + environment
#   Step 7/8: (future) infra + run tests

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
  # ====== Step 1: Parse flags ======
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

  # Export context
  export DOCKAUTO_REQUIRE_INFRA="${require_infra}"
  export DOCKAUTO_IGNORE_TEST_FAILURE="${ignore_test_failure}"
  export DOCKAUTO_TEST_SUITES="${test_suites}"
  export DOCKAUTO_SKIP_TEST="0"
  export DOCKAUTO_NO_SCAN="1"   # test but not scan

  log_debug "test: require_infra=${require_infra}"
  log_debug "test: ignore_test_failure=${ignore_test_failure}"
  log_debug "test: test_suites=${test_suites}"

  # ====== Step 2 VALIDATE config + environment ======
  source "${DOCKAUTO_ROOT_DIR}/lib/config.sh"
  source "${DOCKAUTO_ROOT_DIR}/lib/validate.sh"

  dockauto_config_load "${DOCKAUTO_CONFIG_FILE}" "${DOCKAUTO_PROFILE}"
  dockauto_validate_environment
  dockauto_validate_config

  log_info "Starting test pipeline (Step 7/8 not implemented yet)."
  log_info "Config file: ${DOCKAUTO_CONFIG_FILE}, profile: ${DOCKAUTO_PROFILE:-default}"
  log_info "Suites: ${DOCKAUTO_EFFECTIVE_TEST_SUITES:-<from config>}"

  if [[ "${require_infra}" -eq 1 ]]; then
    log_info "Infra (db/broker) will be required for tests."
  fi

  if [[ "${ignore_test_failure}" -eq 1 ]]; then
    log_info "Test failures will not fail the command (ignore-test-failure)."
  fi

  # TODO:
  #   - reuse built image (from cache)
  #   - dockauto_provision_infra_for_tests
  #   - run tests inside app container
  #   - teardown infra (Step 9)
}
