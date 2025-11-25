#!/usr/bin/env bash
set -euo pipefail

dockauto_validate_environment() {
  log_debug "Validating environment (docker, yq, jq, trivy, syft, language tool...)"

  local missing=0
  for cmd in docker yq jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_error "Required command '$cmd' not found in PATH. Please install it first."
      missing=1
    fi
  done

  if [[ "$missing" -ne 0 ]]; then
    log_error "Please install the missing tools above and retry."
    exit 1
  fi

  # Language-specific tools (best-effort warning)
  case "${DOCKAUTO_CFG_LANGUAGE:-}" in
    node)
      if ! command -v node >/dev/null 2>&1; then
        log_warn "Node.js (node) is not installed. Local commands like 'npm test' may fail. Install from https://nodejs.org/."
      fi
      ;;
    python)
      if ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
        log_warn "Python is not installed. Local 'pytest' may fail. Install Python 3.x first."
      fi
      ;;
    java)
      if ! command -v java >/dev/null 2>&1; then
        log_warn "Java runtime (java) not found. Tests/build commands may fail. Install a JDK (OpenJDK/Temurin...)."
      fi
      ;;
  esac

  # Security tooling
  export DOCKAUTO_SCAN_AVAILABLE=1
  if [[ "${DOCKAUTO_NO_SCAN:-0}" -eq 1 ]]; then
    log_info "Security scan disabled via --no-scan."
    DOCKAUTO_SCAN_AVAILABLE=0
  else
    local need_scan=0
    if [[ "${DOCKAUTO_CFG_SECURITY_SCAN_ENABLED:-false}" == "true" ]]; then
      need_scan=1
    fi
    if [[ "${DOCKAUTO_CFG_SECURITY_SBOM_ENABLED:-false}" == "true" ]]; then
      need_scan=1
    fi
    if [[ "$need_scan" -eq 1 ]]; then
      if ! command -v trivy >/dev/null 2>&1; then
        log_warn "Trivy not found. Security scan may be skipped. Install: https://aquasecurity.github.io/trivy/"
        DOCKAUTO_SCAN_AVAILABLE=0
      fi
      if ! command -v syft >/dev/null 2>&1; then
        log_warn "Syft not found. SBOM generation may be skipped. Install: https://github.com/anchore/syft"
        DOCKAUTO_SCAN_AVAILABLE=0
      fi
    fi
  fi
}

dockauto_validate_config() {
  local json="${DOCKAUTO_CONFIG_JSON:-}"
  if [[ -z "$json" || ! -f "$json" ]]; then
    log_error "Internal error: DOCKAUTO_CONFIG_JSON not set or file missing."
    exit 1
  fi

  # Is x-dockauto present?
  local has_meta
  has_meta="$(jq 'has("x-dockauto")' "$json")"
  if [[ "$has_meta" != "true" ]]; then
    log_error "Missing top-level 'x-dockauto' block in ${DOCKAUTO_CONFIG_FILE}."
    exit 1
  fi

  # Project basic
  if [[ -z "${DOCKAUTO_CFG_PROJECT_NAME:-}" ]]; then
    log_error "x-dockauto.project.name is required."
    exit 1
  fi

  if [[ -z "${DOCKAUTO_CFG_LANGUAGE:-}" ]]; then
    log_error "x-dockauto.project.language is required."
    exit 1
  fi

  local supported_langs="node python java"
  local lang_ok=0
  for l in $supported_langs; do
    if [[ "$l" == "${DOCKAUTO_CFG_LANGUAGE}" ]]; then
      lang_ok=1
      break
    fi
  done
  if [[ "$lang_ok" -ne 1 ]]; then
    log_error "Unsupported language '${DOCKAUTO_CFG_LANGUAGE}'. Supported: ${supported_langs}."
    exit 1
  fi

  if [[ -z "${DOCKAUTO_CFG_LANGUAGE_VERSION:-}" ]]; then
    log_warn "x-dockauto.project.language_version is not set; consider pinning language version."
  fi

  if [[ -z "${DOCKAUTO_CFG_MAIN_SERVICE:-}" ]]; then
    log_error "x-dockauto.project.main_service is required."
    exit 1
  fi

  # main_service exists in services?
  local has_main_service
  has_main_service="$(jq -r --arg svc "${DOCKAUTO_CFG_MAIN_SERVICE}" '.services | has($svc)' "$json")"
  if [[ "$has_main_service" != "true" ]]; then
    log_error "Main service '${DOCKAUTO_CFG_MAIN_SERVICE}' does not exist in services{}."
    exit 1
  fi

  if [[ -z "${DOCKAUTO_CFG_MAIN_BUILD_CONTEXT:-}" ]]; then
    log_warn "Service '${DOCKAUTO_CFG_MAIN_SERVICE}' has no build.context; Docker will default to '.', check if this is expected."
  fi

  # profile
  if [[ -n "${DOCKAUTO_PROFILE:-}" ]]; then
    local profile_exists
    profile_exists="$(jq -r --arg p "${DOCKAUTO_PROFILE}" '."x-dockauto".profiles // {} | has($p)' "$json")"
    if [[ "$profile_exists" != "true" ]]; then
      log_error "Requested profile '${DOCKAUTO_PROFILE}' does not exist under x-dockauto.profiles."
      exit 1
    fi
  fi

  # basic services
  if [[ -z "${DOCKAUTO_CFG_SERVICES_LIST:-}" ]]; then
    log_error "No services defined under services{}."
    exit 1
  fi

  # tests
  if [[ "${DOCKAUTO_CFG_TESTS_ENABLED:-false}" == "true" && "${DOCKAUTO_SKIP_TEST:-0}" -ne 1 ]]; then
    local effective_suites_raw
    if [[ -n "${DOCKAUTO_TEST_SUITES:-}" ]] then
      effective_suites_raw="${DOCKAUTO_TEST_SUITES}"
    fi

    if [[ -z "$effective_suites_raw" ]]; then
      log_error "Tests are enabled but no default_suites configured and no --test provided."
      exit 1
    fi

    local effective_suites=""
    IFS=',' read -r -a _arr <<< "$effective_suites_raw"
    for s in "${_arr[@]}"; do
      s="$(echo "$s" | xargs)}"  # trim
      if [[ -n "$s" ]]; then
        if [[ -n "$effective_suites" ]]; then
          effective_suites+=" "
        fi
        effective_suites+="$s"
      fi
    done

    export DOCKAUTO_EFFECTIVE_TEST_SUITES="${effective_suites}"

    local missing_suite=0
    for suite in $effective_suites; do
      local exists
      exists="$(jq -r --arg s "$suite" '."x-dockauto".tests.suites // {} | has($s)' "$json")"
      if [[ "$exists" != "true" ]]; then
        log_error "Test suite '${suite}' not found under x-dockauto.tests.suites."
        missing_suite=1
        continue
      fi
      local cmd
      cmd="$(jq -r --arg s "$suite" '."x-dockauto".tests.suites[$s].cmd // empty' "$json")"
      if [[ -z "$cmd" || "$cmd" == "null" ]]; then
        log_error "Test suite '${suite}' has no 'cmd' configured."
        missing_suite=1
      fi
    done
    if [[ "$missing_suite" -ne 0 ]]; then
      exit 1
    fi
  fi

  # infra mapping for tests
  if [[ "${DOCKAUTO_REQUIRE_INFRA:-0}" -eq 1 || "${DOCKAUTO_CFG_TESTS_ENABLED:-false}" == "true" ]]; then
    local need_infra_names=""
    if [[ -n "${DOCKAUTO_EFFECTIVE_TEST_SUITES:-}" ]]; then
      for suite in ${DOCKAUTO_EFFECTIVE_TEST_SUITES}; do
        local req
        req="$(jq -r --arg s "$suite" '."x-dockauto".tests.suites[$s].requires_infra // [] | .[]?' "$json" 2>/dev/null || true)"
        if [[ -n "$req" ]]; then
          while IFS= read -r r; do
            # Check duplicate
            if [[ -z "$r" ]]; then
              continue
            fi
            if [[ " $need_infra_names " != *" $r "* ]]; then
              need_infra_names+=" $r"
            fi
          done <<< "$req"
        fi
      done
    fi

    local bad_infra=0
    for name in $need_infra_names; do
      local has_service
      has_service="$(jq -r --arg svc "$name" '.services | has($svc)' "$json")"
      if [[ "$has_service" != "true" ]]; then
        log_error "Test requires infra service '${name}' but no such service defined in services{}."
        bad_infra=1
        continue
      fi
      local role
      role="$(jq -r --arg svc "$name" '.services[$svc]["x-dockauto"].role // empty' "$json")"
      if [[ "$role" != "infra" ]]; then
        log_error "Service '${name}' is required as infra but x-dockauto.role != 'infra'."
        bad_infra=1
      fi
    done
    if [[ "$bad_infra" -ne 0 ]]; then
      exit 1
    fi
  fi

  log_success "Config validation OK."
}
