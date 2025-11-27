#!/usr/bin/env bash
set -euo pipefail

# dockauto up/down:
#   Step 1: parse flags
#   Step 2: VALIDATE config + environment
#   Step 7/9: infra up / teardown (future for dev), test infra handled separately

declare -a _dockauto_compose_cmd=()

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

  # TODO: dev infra using docker compose (project dockauto_dev)
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

# ====== Step 7 (test) – Resolve infra needed for tests ======
dockauto_infra_required_for_tests() {
  local json="${DOCKAUTO_CONFIG_JSON:-}"
  local names=""

  if [[ -z "$json" || ! -f "$json" ]]; then
    echo ""
    return
  fi

  # If we already have EFFECTIVE_TEST_SUITES, re-use
  if [[ -z "${DOCKAUTO_EFFECTIVE_TEST_SUITES:-}" ]]; then
    echo ""
    return
  fi

  for suite in ${DOCKAUTO_EFFECTIVE_TEST_SUITES}; do
    local req
    req="$(jq -r --arg s "$suite" '."x-dockauto".tests.suites[$s].requires_infra // [] | .[]?' "$json" 2>/dev/null || true)"
    if [[ -n "$req" ]]; then
      while IFS= read -r r; do
        [[ -z "$r" ]] && continue
        if [[ " $names " != *" $r "* ]]; then
          names+=" $r"
        fi
      done <<< "$req"
    fi
  done

  # fallback: if --infra flag nhưng suite không khai requires_infra -> dùng toàn bộ infra services
  if [[ -z "$names" && "${DOCKAUTO_REQUIRE_INFRA:-0}" -eq 1 ]]; then
    names="${DOCKAUTO_CFG_INFRA_SERVICES:-}"
  fi

  echo "$names"
}

dockauto_provision_infra_for_tests() {
  if [[ "${DOCKAUTO_CFG_TESTS_ENABLED:-false}" != "true" && "${DOCKAUTO_REQUIRE_INFRA:-0}" -ne 1 ]]; then
    log_debug "Tests are disabled and --infra not set; skipping infra provision."
    return 0
  fi

  local infra_services
  infra_services="$(dockauto_infra_required_for_tests)"
  if [[ -z "$infra_services" ]]; then
    log_info "No infra services required for current test suites; skipping Step 7."
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    log_error "docker not found; cannot provision infra for tests."
    return 1
  fi

  if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    log_error "docker compose/docker-compose not found; cannot provision infra for tests."
    return 1
  fi

  local project_root="${DOCKAUTO_PROJECT_ROOT:-$(pwd)}"
  local compose_file="${DOCKAUTO_CONFIG_FILE}"

  local short_hash="${DOCKAUTO_BUILD_HASH:0:12}"
  local compose_project="dockauto_test_${short_hash}"

  log_debug "STATE: INFRA"
  log_info "Provisioning infra for tests (Step 7) using docker compose project: ${compose_project}"
  log_info "Infra services: ${infra_services}"

  (
    cd "${project_root}"
    COMPOSE_PROJECT_NAME="${compose_project}" \
      dockauto_docker_compose -f "${compose_file}" up -d ${infra_services}
  )

  # Basic healthcheck loop (if images have HEALTHCHECK)
  for svc in ${infra_services}; do
    local container_name="${compose_project}_${svc}_1"
    log_info "Waiting for infra service '${svc}' (container: ${container_name}) to become healthy (if healthcheck defined)..."

    local max_retries=30
    local sleep_sec=3
    local i=0
    local healthy=0

    while (( i < max_retries )); do
      if ! docker inspect "${container_name}" >/dev/null 2>&1; then
        log_warn "Container ${container_name} not found yet..."
      else
        local health
        health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container_name}" 2>/dev/null || echo "none")"
        if [[ "$health" == "healthy" || "$health" == "none" ]]; then
          healthy=1
          break
        fi
      fi
      ((i++))
      sleep "${sleep_sec}"
    done

    if [[ "$healthy" -eq 1 ]]; then
      log_success "Infra service '${svc}' is ready (or no healthcheck defined)."
    else
      log_warn "Timeout waiting for infra service '${svc}' to be healthy."
    fi
  done

  mkdir -p "${project_root}/.dockauto"
  cat >"${project_root}/.dockauto/last_test_infra.json" <<EOF
{
  "compose_project": "${compose_project}",
  "services": [$(printf '"%s",' ${infra_services} | sed 's/,$//')],
  "build_hash": "${DOCKAUTO_BUILD_HASH}"
}
EOF

  log_debug "Recorded test infra metadata at .dockauto/last_test_infra.json"
}

# ====== Step 9 (test) – Teardown infra ======
dockauto_teardown_infra_for_tests() {
  local project_root="${DOCKAUTO_PROJECT_ROOT:-$(pwd)}"
  local meta_file="${project_root}/.dockauto/last_test_infra.json"

  if [[ ! -f "$meta_file" ]]; then
    log_debug "No last_test_infra.json found; nothing to teardown."
    return 0
  fi

  local compose_project
  compose_project="$(jq -r '.compose_project // ""' "$meta_file" 2>/dev/null || echo "")"

  if [[ -z "$compose_project" ]]; then
    log_warn "last_test_infra.json has no compose_project; skipping teardown."
    return 0
  fi

  log_debug "STATE: CLEANUP"
  log_info "Tearing down test infra (compose project: ${compose_project})"

  (
    cd "${project_root}"
    COMPOSE_PROJECT_NAME="${compose_project}" \
      dockauto_docker_compose -f "${DOCKAUTO_CONFIG_FILE}" down --remove-orphans
  )

  rm -f "$meta_file"
  log_success "Test infra torn down."
}

# ----- helper: docker compose wrapper -----
dockauto_docker_compose() {
  # Detect once
  if [[ ${#_dockauto_compose_cmd[@]} -eq 0 ]]; then
    if docker compose version >/dev/null 2>&1; then
      _dockauto_compose_cmd=(docker compose)
    elif command -v docker-compose >/dev/null 2>&1; then
      _dockauto_compose_cmd=(docker-compose)
    else
      log_error "Neither 'docker compose' nor 'docker-compose' is available. Please install Docker Compose plugin."
      return 1
    fi
  fi

  "${_dockauto_compose_cmd[@]}" "$@"
}