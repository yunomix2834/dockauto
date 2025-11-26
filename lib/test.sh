#!/usr/bin/env bash
set -euo pipefail

# dockauto test:
#   State machine (simple): VALIDATE -> HASH -> INFRA -> TEST -> CLEANUP
#   Step 1: parse test flags
#   Step 2: VALIDATE config + environment
#   Step 3: HASH + tìm image từ cache
#   Step 7/8/9: infra + run tests + teardown

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

  log_debug "STATE: VALIDATE"

  # ====== Step 2 VALIDATE config + environment ======
  source "${DOCKAUTO_ROOT_DIR}/lib/config.sh"
  source "${DOCKAUTO_ROOT_DIR}/lib/validate.sh"

  dockauto_config_load "${DOCKAUTO_CONFIG_FILE}" "${DOCKAUTO_PROFILE}"
  dockauto_validate_environment
  dockauto_validate_config

  # ====== Step 3: HASH + fetch image from cache ======
  log_debug "STATE: HASH"
  source "${DOCKAUTO_ROOT_DIR}/lib/hash.sh"

  dockauto_hash_calculate
  dockauto_hash_check_cache

  if [[ "${DOCKAUTO_CACHE_HIT:-0}" -ne 1 ]]; then
    log_error "No cached build found for BUILD_HASH=${DOCKAUTO_BUILD_HASH}."
    log_error "Please run 'dockauto build' first."
    return 1
  fi

  local image_tag
  image_tag="$(jq -r '.image_tag // empty' <<<"${DOCKAUTO_CACHE_ENTRY_JSON}")"
  if [[ -z "$image_tag" || "$image_tag" == "null" ]]; then
    log_error "Cached build entry does not contain image_tag; please rebuild using 'dockauto build'."
    return 1
  fi

  export DOCKAUTO_IMAGE_TAG="${image_tag}"

  log_info "Using cached image for tests: ${image_tag}"
  log_info "Config file: ${DOCKAUTO_CONFIG_FILE}, profile: ${DOCKAUTO_PROFILE:-default}"
  log_info "Suites: ${DOCKAUTO_EFFECTIVE_TEST_SUITES:-<from config>}"

  if [[ "${require_infra}" -eq 1 ]]; then
    log_info "Infra (db/broker) will be required for tests."
  fi

  if [[ "${ignore_test_failure}" -eq 1 ]]; then
    log_info "Test failures will not fail the command (ignore-test-failure)."
  fi

  # ====== Step 7/8/9: infra + run tests + teardown ======
  source "${DOCKAUTO_ROOT_DIR}/lib/infra.sh"

  log_debug "STATE: TEST"
  if ! dockauto_run_tests_for_image "${image_tag}"; then
    local rc=$?
    if [[ "${ignore_test_failure}" -eq 1 ]]; then
      log_warn "Tests failed (rc=${rc}) but --ignore-test-failure is set."
      return 0
    fi
    log_debug "STATE: CLEANUP"
    log_error "Test pipeline failed."
    return "$rc"
  fi

  log_debug "STATE: CLEANUP"
  log_success "Test pipeline completed."
}

# ====== Core test runner (Step 8) – dùng chung cho build & test ======
dockauto_run_tests_for_image() {
  local image_tag="$1"

  if [[ "${DOCKAUTO_CFG_TESTS_ENABLED:-false}" != "true" ]]; then
    log_info "Tests are disabled in config (x-dockauto.tests.enabled=false); skipping Step 8."
    return 0
  fi

  if [[ -z "${DOCKAUTO_EFFECTIVE_TEST_SUITES:-}" ]]; then
    log_warn "No effective test suites resolved; skipping tests."
    return 0
  fi

  local json="${DOCKAUTO_CONFIG_JSON}"
  local suites_no_infra=()
  local suites_with_infra=()

  # Divine suites with/without infra
  for suite in ${DOCKAUTO_EFFECTIVE_TEST_SUITES}; do
    local count
    count="$(jq -r --arg s "$suite" '."x-dockauto".tests.suites[$s].requires_infra // [] | length' "$json" 2>/dev/null || echo "0")"
    if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
      suites_with_infra+=( "$suite" )
    else
      suites_no_infra+=( "$suite" )
    fi
  done

  local overall_rc=0

  for suite in "${suites_no_infra[@]}"; do
    if ! dockauto_run_single_suite "$suite" "$image_tag" 0; then
      overall_rc=1
      if [[ "${DOCKAUTO_IGNORE_TEST_FAILURE:-0}" -ne 1 ]]; then
        log_error "Stopping tests because suite '${suite}' failed and ignore-test-failure is not set."
        return 1
      else
        log_warn "Suite '${suite}' failed but ignore-test-failure is set; continuing."
      fi
    fi
  done

  # If does not require infra, skip suites with infra
  if (( ${#suites_with_infra[@]} == 0 )) && [[ "${DOCKAUTO_REQUIRE_INFRA:-0}" -ne 1 ]]; then
    return "$overall_rc"
  fi

  if ! dockauto_provision_infra_for_tests; then
    log_error "Failed to provision infra for tests."
    return 1
  fi

  for suite in "${suites_with_infra[@]}"; do
    if ! dockauto_run_single_suite "$suite" "$image_tag" 1; then
      overall_rc=1
      if [[ "${DOCKAUTO_IGNORE_TEST_FAILURE:-0}" -ne 1 ]]; then
        log_error "Stopping tests because suite '${suite}' failed and ignore-test-failure is not set."
        break
      else
        log_warn "Suite '${suite}' failed but ignore-test-failure is set; continuing."
      fi
    fi
  done

  dockauto_teardown_infra_for_tests

  return "$overall_rc"
}

# ----- Run single suite inside image (docker run) -----
dockauto_run_single_suite() {
  local suite="$1"
  local image_tag="$2"
  local needs_infra="$3"  # 0 or 1

  local json="${DOCKAUTO_CONFIG_JSON}"
  local cmd
  cmd="$(jq -r --arg s "$suite" '."x-dockauto".tests.suites[$s].cmd // empty' "$json")"

  if [[ -z "$cmd" || "$cmd" == "null" ]]; then
    log_error "Test suite '${suite}' has no 'cmd' configured."
    return 1
  fi

  local docker_args=(run --rm)

  # If suite needs infra -> attach to test infra's compose network
  if [[ "$needs_infra" -eq 1 ]]; then
    local project_root="${DOCKAUTO_PROJECT_ROOT:-$(pwd)}"
    local meta_file="${project_root}/.dockauto/last_test_infra.json"
    if [[ -f "$meta_file" ]]; then
      local compose_project
      compose_project="$(jq -r '.compose_project // ""' "$meta_file" 2>/dev/null || echo "")"
      if [[ -n "$compose_project" ]]; then
        local first_net
        first_net="$(
          jq -r ".services[\"${DOCKAUTO_CFG_MAIN_SERVICE}\"].networks // [] |
            if type == \"array\" then .[0] // \"\" else (keys | .[0]) // \"\" end" \
            "$json" 2>/dev/null || echo ""
        )"
        if [[ -n "$first_net" ]]; then
          docker_args+=(--network "${compose_project}_${first_net}")
        fi
      fi
    fi
  fi

  log_info "Running test suite '${suite}' in image ${image_tag} (needs_infra=${needs_infra})"
  log_debug "  cmd: ${cmd}"

  if ! docker "${docker_args[@]}" "${image_tag}" sh -lc "$cmd"; then
    log_error "Test suite '${suite}' failed."
    return 1
  fi

  log_success "Test suite '${suite}' passed."
  return 0
}
