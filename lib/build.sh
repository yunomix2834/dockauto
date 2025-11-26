#!/usr/bin/env bash
set -euo pipefail

# dockauto build:
#   FUTURE CALL state machine: VALIDATE -> HASH -> BUILD -> SCAN -> INFRA -> TEST -> CLEANUP
#   Step 1: CLI & build flags
#   Step 2: VALIDATE (config + environment)
#   Step 4: Generate Dockerfile from template (if needed)
#   Step 3: HASH (CONFIG/SOURCE/BUILD + cache check)
#   Step 5+: BUILD, SCAN, INFRA, TEST, CLEANUP (future)

dockauto_cmd_build_usage() {
  cat <<'EOF'
Usage: dockauto build [options]

Options:
  --infra                  Require infra (db/broker) for tests
  --skip-test              Skip running tests after build
  --ignore-test-failure    Do not fail build if tests fail (just warn)
  --no-scan                Skip security scan (Trivy/SBOM)
  --test SUITES            Comma-separated test suites (e.g. "unit,integration")

Examples:
  dockauto build
  dockauto build --skip-test --no-scan
  dockauto build --infra --test integration
  dockauto build --ignore-test-failure --test unit,integration
EOF
}

dockauto_cmd_build() {
  # ====== Step 1: Parse build flags ======
  local require_infra=0
  local skip_test=0
  local ignore_test_failure=0
  local no_scan=0
  # "unit, integration" or null = config default
  local test_suites=""

  # Parse build-specific flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --infra)
        require_infra=1
        shift
        ;;
      --skip-test|--skip-tests)
        skip_test=1
        shift
        ;;
      --ignore-test-failure)
        ignore_test_failure=1
        shift
        ;;
      --no-scan)
        no_scan=1
        shift
        ;;
      --test|--tests)
        test_suites="${2:-}"
        shift 2
        ;;
      -h|--help)
        dockauto_cmd_build_usage
        return 0
        ;;
      *)
        log_error "Unknown option for build: $1"
        dockauto_cmd_build_usage
        return 1
        ;;
    esac
  done

  # Export context for Step 2
  export DOCKAUTO_REQUIRE_INFRA="${require_infra}"
  export DOCKAUTO_SKIP_TEST="${skip_test}"
  export DOCKAUTO_IGNORE_TEST_FAILURE="${ignore_test_failure}"
  export DOCKAUTO_NO_SCAN="${no_scan}"
  export DOCKAUTO_TEST_SUITES="${test_suites}"

  log_debug "build: require_infra=${require_infra}"
  log_debug "build: skip_test=${skip_test}"
  log_debug "build: ignore_test_failure=${ignore_test_failure}"
  log_debug "build: no_scan=${no_scan}"
  log_debug "build: test_suites=${test_suites}"

  # ====== Step 2 VALIDATE config + environment ======
  source "${DOCKAUTO_ROOT_DIR}/lib/config.sh"
  source "${DOCKAUTO_ROOT_DIR}/lib/validate.sh"

  dockauto_config_load "${DOCKAUTO_CONFIG_FILE}" "${DOCKAUTO_PROFILE}"
  dockauto_validate_environment
  dockauto_validate_config

  # ====== Step 3: HASH (CONFIG / SOURCE / BUILD + cache check) ======
  source "${DOCKAUTO_ROOT_DIR}/lib/hash.sh"

  dockauto_hash_calculate
  dockauto_hash_check_cache

  log_info "CONFIG_HASH: ${DOCKAUTO_CONFIG_HASH}"
  log_info "SOURCE_HASH: ${DOCKAUTO_SOURCE_HASH}"
  log_info "BUILD_HASH : ${DOCKAUTO_BUILD_HASH}"
  log_info "Template version: ${DOCKAUTO_TEMPLATE_VERSION}"

  if [[ "${DOCKAUTO_CACHE_HIT:-0}" -eq 1 ]]; then
    log_info "Cache: HIT (existing entry in .dockauto/cache.json for this BUILD_HASH)."
  else
    log_info "Cache: MISS (no entry for this BUILD_HASH, will build new image in Step 5)."
  fi

  # ====== Step 4+ (Not implement) ======
  #   - BUILD:   docker build ...
  #   - SCAN:    dockauto_scan_image ...
  #   - INFRA:   infra up for tests ...
  #   - TEST:    run test suites ...
  #   - CLEANUP: infra teardown ...

  log_info "Starting build pipeline (HASH -> BUILD -> SCAN -> INFRA -> TEST -> CLEANUP in future steps)."
  log_info "Config file: ${DOCKAUTO_CONFIG_FILE}, profile: ${DOCKAUTO_PROFILE:-default}"

  if [[ "${skip_test}" -eq 1 ]]; then
    log_info "Tests will be skipped."
  else
    log_info "Tests will be run (suites: ${DOCKAUTO_EFFECTIVE_TEST_SUITES:-<from config>})."
  fi

  if [[ "${no_scan}" -eq 1 ]]; then
    log_info "Security scan will be skipped."
  else
    log_info "Security scan will run (if tools available)."
  fi

  if [[ "${require_infra}" -eq 1 ]]; then
    log_info "Infra (db/broker) will be required for tests."
  fi

  if [[ "${ignore_test_failure}" -eq 1 ]]; then
    log_info "Test failures will not fail the build (ignore-test-failure)."
  fi
}