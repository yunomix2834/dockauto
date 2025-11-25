#!/usr/bin/env bash
set -euo pipefail

dockauto_config_load() {
  local config_file="$1"
  # Profile: dev, ci, etc
  local profile="${2:-}"

  if [[ ! -f "$config_file" ]]; then
    log_error "Config file not found: ${config_file}"
    exit 1
  fi

  # yq + jq is primary dependency for Step 2
  if ! command -v yq >/dev/null 2>&1; then
    log_error "Required tool 'yq' not found. Please install yq first."
    exit 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    log_error "Required tool 'jq' not found. Please install jq first."
    exit 1
  fi

  mkdir -p .dockauto

  local json_file=".dockauto/config.json"

  log.debug "Converting YAML to JSON with yq + jq..."
  if ! yq eval -o=json '.' "$config_file" | jq '.' > "$json_file"; then
    log_error "Failed to parse ${config_file} via yq/jq."
    exit 1
  fi

  export DOCKAUTO_CONFIG_JSON="${json_file}"
  export DOCKAUTO_CFG_PROFILE_REQUESTED="${profile}"

  # === Extract x-dockauto.project ===
  local project_name
  project_name="$(jq -r '."x-dockauto".project.name // empty' "$json_file")"
  local main_service
  main_service="$(jq -r '."x-dockauto".project.main_service // empty' "$json_file")"
  local language
  language="$(jq -r '."x-dockauto".project.language // empty' "$json_file")"
  local language_version
  language_version="$(jq -r '."x-dockauto".project.language_version // empty' "$json_file")"

  export DOCKAUTO_CFG_PROJECT_NAME="${project_name}"
  export DOCKAUTO_CFG_MAIN_SERVICE="${main_service}"
  export DOCKAUTO_CFG_LANGUAGE="${language}"
  export DOCKAUTO_CFG_LANGUAGE_VERSION="${language_version}"

  # === Build.lockfiles ===
  local lockfiles
  lockfiles="$(jq -r '."x-dockauto".build.lockfiles // [] | join(" ")' "$json_file")"
  export DOCKAUTO_CFG_BUILD_LOCKFILES="${lockfiles}"

  # === Tests ===
  local tests_enabled
  tests_enabled="$(jq -r '."x-dockauto".tests.enabled // false' "$json_file")"
  local default_suites
  default_suites="$(jq -r '."x-dockauto".tests.default_suites // [] | join(",")' "$json_file")"
  local suites_json
  suites_json="$(jq -r '."x-dockauto".tests.suites // {}' "$json_file")"

  # === Security ===
  local scan_enabled sbom_enabled scan_tool sbom_tool scan_fail_on
  scan_enabled="$(jq -r '."x-dockauto".security.scan.enabled // false' "$json_file")"
  sbom_enabled="$(jq -r '."x-dockauto".security.sbom.enabled // false' "$json_file")"
  scan_tool="$(jq -r '."x-dockauto".security.scan.tool // "trivy"' "$json_file")"
  sbom_tool="$(jq -r '."x-dockauto".security.sbom.tool // "syft"' "$json_file")"
  scan_fail_on="$(jq -r '."x-dockauto".security.scan.fail_on // [] | join(",")' "$json_file")"

  export DOCKAUTO_CFG_SECURITY_SCAN_ENABLED="${scan_enabled}"
  export DOCKAUTO_CFG_SECURITY_SBOM_ENABLED="${sbom_enabled}"
  export DOCKAUTO_CFG_SECURITY_SCAN_TOOL="${scan_tool}"
  export DOCKAUTO_CFG_SECURITY_SBOM_TOOL="${sbom_tool}"
  export DOCKAUTO_CFG_SECURITY_SCAN_FAIL_ON="${scan_fail_on}"

  # === Services summary ===
  local services_list
  services_list="$(jq -r '.services | keys[]?' "$json_file" || true)"
  export DOCKAUTO_CFG_SERVICES_LIST="${services_list}"

  local infra_services
  infra_services="$(jq -r '.services | to_entries[] | select(.value["x-dockauto"].role == "infra") | .key' "$json_file" || true)"
  export DOCKAUTO_CFG_INFRA_SERVICES="${infra_services}"

  local app_services
  app_services="$(jq -r '.services | to_entries[] | select(.value["x-dockauto"].role == "app") | .key' "$json_file" || true)"
  export DOCKAUTO_CFG_APP_SERVICES="${app_services}"

  # Build context cho main_service
  local main_build_context
  main_build_context="$(jq -r ".services[\"${main_service}\"].build.context // \"\"" "$json_file" 2>/dev/null || echo "")"
  export DOCKAUTO_CFG_MAIN_BUILD_CONTEXT="${main_build_context}"

  log_debug "Loaded config: project='${DOCKAUTO_CFG_PROJECT_NAME}', language=${DOCKAUTO_CFG_LANGUAGE}, main_service=${DOCKAUTO_CFG_MAIN_SERVICE}"
}

dockauto_config_get_language() {
  echo "${DOCKAUTO_CFG_LANGUAGE:-}"
}
