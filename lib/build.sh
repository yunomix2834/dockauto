#!/usr/bin/env bash
set -euo pipefail

# dockauto build:
#   State machine: INIT -> VALIDATE -> HASH -> BUILD -> SCAN -> INFRA -> TEST -> CLEANUP
#   Step 1: CLI & build flags
#   Step 2: VALIDATE (config + environment)
#   Step 3: Generate Dockerfile from template (if needed)
#   Step 4: HASH (CONFIG/SOURCE/BUILD + cache check)
#   Step 5: BUILD image
#   Step 6: SCAN (optional)
#   Step 7: INFRA (for tests, optional)
#   Step 8: TEST (inside built image)
#   Step 9: CLEANUP infra (for tests)

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

# Build pipeline
dockauto_pipeline_build() {
  log_debug "STATE: INIT"
  dockauto_step_build_validate_and_config
  dockauto_step_build_ensure_dockerfile
  dockauto_step_build_hash_and_cache
  dockauto_step_build_image
  dockauto_step_build_scan
  dockauto_step_build_tests
}


dockauto_cmd_build() {
  log_debug "STATE: INIT"

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
      --infra)                                      require_infra=1; shift ;;
      --skip-test|--skip-tests)                     skip_test=1; shift ;;
      --ignore-test-failure)                        ignore_test_failure=1; shift ;;
      --no-scan)                                    no_scan=1; shift ;;
      --test|--tests)                               test_suites="${2:-}"; shift 2 ;;
      -h|--help)                                    dockauto_cmd_build_usage; return 0 ;;
      *) log_error "Unknown option for build: $1";  dockauto_cmd_build_usage; return 1 ;;
    esac
  done

  # Export context for Step 2
  DOCKAUTO_REQUIRE_INFRA="$require_infra"
  DOCKAUTO_SKIP_TEST="$skip_test"
  DOCKAUTO_IGNORE_TEST_FAILURE="$ignore_test_failure"
  DOCKAUTO_NO_SCAN="$no_scan"
  DOCKAUTO_TEST_SUITES="$test_suites"

  log_debug "build: require_infra=${require_infra}"
  log_debug "build: skip_test=${skip_test}"
  log_debug "build: ignore_test_failure=${ignore_test_failure}"
  log_debug "build: no_scan=${no_scan}"
  log_debug "build: test_suites=${test_suites}"

  dockauto_pipeline_build
}

dockauto_step_build_validate_and_config() {
  # ====== Step 2 VALIDATE config + environment ======
  log_debug "STATE: VALIDATE"

  source "${DOCKAUTO_ROOT_DIR}/lib/config.sh"
  source "${DOCKAUTO_ROOT_DIR}/lib/validate.sh"

  dockauto_config_load "${DOCKAUTO_CONFIG_FILE}" "${DOCKAUTO_PROFILE}"
  dockauto_validate_environment
  dockauto_validate_config
}

dockauto_step_build_ensure_dockerfile() {
  # ====== Step 3: Ensure/Generate Dockerfile from Template ======
  source "${DOCKAUTO_ROOT_DIR}/lib/dockerfile.sh"
  dockauto_ensure_dockerfile
}

dockauto_step_build_hash_and_cache() {
  # ====== Step 4: HASH (CONFIG / SOURCE / BUILD + cache check) ======
  log_debug "STATE: HASH"
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
}

dockauto_step_build_image() {
  # ====== Step 5: BUILD image ======
  log_debug "STATE: BUILD"
  dockauto_build_image
}

dockauto_step_build_scan() {
  # ====== Step 6: SCAN image (optional) ======
  log_debug "STATE: SCAN"
  source "${DOCKAUTO_ROOT_DIR}/lib/scan.sh"
  if [[ "${DOCKAUTO_NO_SCAN:-0}" -eq 1 ]]; then
    log_info "Security scan is disabled via --no-scan."
  else
    dockauto_scan_image "${DOCKAUTO_IMAGE_TAG}"
  fi
}

dockauto_step_build_tests() {
  # ====== Step 7 + 8 + 9: TEST + INFRA + CLEANUP ======
  source "${DOCKAUTO_ROOT_DIR}/lib/infra.sh"
  source "${DOCKAUTO_ROOT_DIR}/lib/test.sh"

  if [[ "${DOCKAUTO_SKIP_TEST:-0}" -eq 1 ]]; then
    log_info "Tests are skipped via --skip-test (no infra, no tests)."
    log_debug "STATE: CLEANUP"
    log_info "Build pipeline completed (BUILD + SCAN)."
    return 0
  fi

  log_debug "STATE: TEST"

  # Execute tests with image after build
  if ! dockauto_run_tests_for_image "${DOCKAUTO_IMAGE_TAG}"; then
    local rc=$?
    if [[ "${DOCKAUTO_IGNORE_TEST_FAILURE:-0}" -eq 1 ]]; then
      log_warn "Tests failed (rc=${rc}) but --ignore-test-failure is set; continue."
    else
      log_debug "STATE: CLEANUP"
      log_error "Build pipeline failed due to test failures."
      return "$rc"
    fi
  fi

  log_debug "STATE: CLEANUP"
  log_success "Build pipeline completed (BUILD + SCAN + TEST)."
}

dockauto_build_image() {
  # ====== Step 5: Build image (docker build) ======
  local project_root="${DOCKAUTO_PROJECT_ROOT:-$(pwd)}"
  local ctx="${DOCKAUTO_CFG_MAIN_BUILD_CONTEXT:-.}"
  [[ -z "$ctx" ]] && ctx="."
  local dockerfile_rel="${DOCKAUTO_CFG_MAIN_DOCKERFILE:-Dockerfile}"
  local ctx_abs="${project_root}/${ctx%/}"
  local dockerfile_path="${ctx_abs}/${dockerfile_rel}"

  if [[ ! -f "$dockerfile_path" ]]; then
    log_error "Dockerfile not found at ${dockerfile_path} (after Step 4)."
    return 1
  fi

  local image_name
  image_name="$(jq -r ".services[\"${DOCKAUTO_CFG_MAIN_SERVICE}\"].image // empty" "${DOCKAUTO_CONFIG_JSON}")"
  if [[ -z "$image_name" || "$image_name" == "null" ]]; then
    image_name="${DOCKAUTO_CFG_PROJECT_NAME:-dockauto-app}"
  fi

  local short_hash="${DOCKAUTO_BUILD_HASH:0:12}"
  local image_tag="${image_name}:${short_hash}"

  # Build args from config
  local build_args_json
  build_args_json="$(jq -c ".services[\"${DOCKAUTO_CFG_MAIN_SERVICE}\"].build.args // {}" "${DOCKAUTO_CONFIG_JSON}")"
  local build_args=()
  if [[ "$build_args_json" != "{}" ]]; then
    while IFS='=' read -r k v; do
      [[ -z "$k" ]] && continue
      build_args+=(--build-arg "${k}=${v}")
    done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' <<<"$build_args_json")
  fi

  log_info "Building image: ${image_tag}"
  log_debug "  context   : ${ctx_abs}"
  log_debug "  dockerfile: ${dockerfile_path}"

  (
    cd "$ctx_abs"
    docker build -f "$dockerfile_path" -t "$image_tag" "${build_args[@]}" .
  )

  # Inspect image info
  local inspect_json
  inspect_json="$(docker image inspect "$image_tag" | jq '.[0]')"

  local image_id digest created_at
  image_id="$(jq -r '.Id' <<<"$inspect_json")"
  digest="$(jq -r '.RepoDigests[0] // ""' <<<"$inspect_json")"
  created_at="$(jq -r '.Created' <<<"$inspect_json")"

  log_success "Built image:"
  log_info "  hash   (build) : ${DOCKAUTO_BUILD_HASH}"
  log_info "  image tag      : ${image_tag}"
  log_info "  image id       : ${image_id}"
  log_info "  digest         : ${digest}"
  log_info "  created_at     : ${created_at}"

  # Export for later steps
  export DOCKAUTO_IMAGE_TAG="${image_tag}"
  export DOCKAUTO_IMAGE_ID="${image_id}"

  # Update cache (Step 5: hash → tag → id → digest → created_at)
  local build_entry_json
  build_entry_json="$(
    jq -n \
      --arg tag "${image_tag}" \
      --arg id "${image_id}" \
      --arg digest "${digest}" \
      --arg created "${created_at}" \
      --arg cfg_hash "${DOCKAUTO_CONFIG_HASH}" \
      --arg src_hash "${DOCKAUTO_SOURCE_HASH}" \
      --arg tool_ver "${DOCKAUTO_VERSION:-}" \
      --arg cfg_file "${DOCKAUTO_CONFIG_FILE}" \
      --arg main_service "${DOCKAUTO_CFG_MAIN_SERVICE}" \
      '{
        image_tag: $tag,
        image_id: $id,
        digest: $digest,
        created_at: $created,
        config_hash: $cfg_hash,
        source_hash: $src_hash,
        tool_version: $tool_ver,
        config_file: $cfg_file,
        main_service: $main_service
      }'
  )"

  dockauto_cache_update_build_entry "${build_entry_json}"

  # Save a small report
  mkdir -p "${project_root}/.dockauto"
  cat >"${project_root}/.dockauto/build_report.json" <<<"${build_entry_json}"
}
