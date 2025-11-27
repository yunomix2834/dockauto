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

# ====== Helpers for dev infra ======
_dockauto_check_port_free() {
  local port_spec="$1"
  local host_port="${port_spec%%:*}"

  [[ -z "$host_port" ]] && return 0

  log_debug "Checking host port ${host_port} availability..."

  if command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"$host_port" -sTCP:LISTEN >/dev/null 2>&1; then
      log_error "Host port ${host_port} appears to be in use. Please choose another port or stop the process."
      return 1
    fi
  elif command -v ss >/dev/null 2>&1; then
    if ss -ltn "sport = :${host_port}" | tail -n +2 | grep -q .; then
      log_error "Host port ${host_port} appears to be in use. Please choose another port or stop the process."
      return 1
    fi
  else
    log_warn "Neither 'lsof' nor 'ss' is available; skipping port check for ${host_port}."
  fi
}

_dockauto_ensure_network() {
  local network_name="$1"
  [[ -z "$network_name" ]] && return 0

  if ! command -v docker >/dev/null 2>&1; then
    log_warn "docker not available; cannot check/create network '${network_name}'."
    return 0
  fi

  if docker network ls --format '{{.Name}}' | grep -qx "${network_name}"; then
    log_debug "Docker network '${network_name}' already exists."
    return 0
  fi

  log_info "Docker network '${network_name}' does not exist; creating..."
  if docker network create "${network_name}" >/dev/null 2>&1; then
    log_success "Created Docker network '${network_name}'."
  else
    log_warn "Failed to create Docker network '${network_name}'."
  fi
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

  local project_root="${DOCKAUTO_PROJECT_ROOT:-$(pwd)}"
  local compose_file="${DOCKAUTO_CONFIG_FILE}"
  local infra_services="${DOCKAUTO_CFG_INFRA_SERVICES:-}"

  if [[ -z "$infra_services" ]]; then
    log_warn "No infra services (x-dockauto.role=infra) defined; nothing to bring up."
    return 0
  fi

  # Check port & network if user needs
  if [[ -n "${port_spec}" ]]; then
    if ! _dockauto_check_port_free "${port_spec}"; then
      return 1
    fi
  fi

  if [[ -n "${network_name}" ]]; then
    _dockauto_ensure_network "${network_name}"
  fi

  local dev_project_name="${DOCKAUTO_CFG_PROJECT_NAME:-dockauto}"
  local compose_project="dockauto_dev_${dev_project_name}"

  log_info "Starting dev infra (dockauto up) using compose project: ${compose_project}"
  log_info "Config file: ${compose_file}, profile: ${DOCKAUTO_PROFILE:-default}"
  log_info "Infra services: ${infra_services}"

  if ! command -v docker >/dev/null 2>&1; then
    log_error "docker not found; cannot start dev infra."
    return 1
  fi

  if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    log_error "docker compose/docker-compose not found; cannot start dev infra."
    return 1
  fi

  (
    cd "${project_root}"
    COMPOSE_PROJECT_NAME="${compose_project}" \
      dockauto_docker_compose -f "${compose_file}" up -d ${infra_services}
  )

  mkdir -p "${project_root}/.dockauto"
  cat >"${project_root}/.dockauto/last_dev_infra.json" <<EOF
{
  "compose_project": "${compose_project}",
  "services": [$(printf '"%s",' ${infra_services} | sed 's/,$//')],
  "config_file": "${compose_file}"
}
EOF

  if [[ "${keep_infra}" -eq 1 ]]; then
    log_info "Dev infra will be kept running until you run 'dockauto down'."
  else
    log_info "Dev infra started. Use 'dockauto down' to stop it."
  fi

  log_success "dockauto up completed."
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

  local project_root="${DOCKAUTO_PROJECT_ROOT:-$(pwd)}"
  local meta_file="${project_root}/.dockauto/last_dev_infra.json"

  if [[ ! -f "$meta_file" ]]; then
    log_warn "No dev infra metadata found (.dockauto/last_dev_infra.json); nothing to teardown."
    return 0
  fi

  local compose_project
  compose_project="$(jq -r '.compose_project // ""' "$meta_file" 2>/dev/null || echo "")"
  local cfg_file
  cfg_file="$(jq -r '.config_file // ""' "$meta_file" 2>/dev/null || echo "")"

  if [[ -z "$compose_project" ]]; then
    log_warn "last_dev_infra.json has no compose_project; skipping teardown."
    return 0
  fi

  # If does not save the config_file -> fallback use current DOCKAUTO_CONFIG_FIL
  local compose_file="${cfg_file:-${DOCKAUTO_CONFIG_FILE}}"

  log_info "Stopping dev infra (compose project: ${compose_project})"
  log_debug "Using compose file: ${compose_file}"

  if ! command -v docker >/dev/null 2>&1; then
    log_error "docker not found; cannot teardown dev infra."
    return 1
  fi

  if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    log_error "docker compose/docker-compose not found; cannot teardown dev infra."
    return 1
  fi

  (
    cd "${project_root}"
    COMPOSE_PROJECT_NAME="${compose_project}" \
      dockauto_docker_compose -f "${compose_file}" down --remove-orphans
  )

  rm -f "$meta_file"
  log_success "Dev infra torn down."
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

  # fallback: if --infra flag nhưng suite but not requires_infra -> use all infra services
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