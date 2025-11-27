#!/usr/bin/env bash
set -euo pipefail

# ====== Step 4: Hash ======
# - CONFIG_HASH = dockauto.yml + template_version (+ dockauto version)
# - SOURCE_HASH = hash(source code + lockfiles) with ignore
# - BUILD_HASH  = sha256(CONFIG_HASH + SOURCE_HASH)
# - Check cache .dockauto/cache.json (if exists)

dockauto_hash_calculate() {
  local project_root="${DOCKAUTO_PROJECT_ROOT:-$(pwd)}"
  local config_file="${DOCKAUTO_CONFIG_FILE}"

  local sha_cmd=""
  if command -v sha256sum >/dev/null 2>&1; then
    sha_cmd="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    sha_cmd="shasum -a 256"
  else
    log_error "Neither 'sha256sum' nor 'shasum' is available. Please install one of them."
    exit 1
  fi

  if ! command -v tar >/dev/null 2>&1; then
    log_error "Required command 'tar' not found."
    exit 1
  fi

  mkdir -p "${project_root}/.dockauto"

  # Detect template version from Dockerfile
  local ctx="${DOCKAUTO_CFG_MAIN_BUILD_CONTEXT:-.}"
  [[ -z "$ctx" ]] && ctx="."
  local dockerfile_rel="${DOCKAUTO_CFG_MAIN_DOCKERFILE:-Dockerfile}"
  local dockerfile_path="${project_root}/${ctx%/}/${dockerfile_rel}"

  local template_version="unknown"
  if [[ -f "$dockerfile_path" ]]; then
    template_version="$(
      grep -E '^# *dockauto-template-version:' "$dockerfile_path" 2>/dev/null \
        | head -n1 \
        | sed -E 's/^# *dockauto-template-version:[[:space:]]*//'
    )"
    [[ -z "$template_version" ]] && template_version="unknown"
  else
    template_version="missing"
  fi
  export DOCKAUTO_TEMPLATE_VERSION="${template_version}"

  # CONFIG_HASH
  local config_hash
  config_hash="$(
    {
      cat "$config_file"
      echo
      echo "TEMPLATE_VERSION=${template_version}"
      echo "DOCKAUTO_VERSION=${DOCKAUTO_VERSION:-}"
    } | eval "$sha_cmd" | awk '{print $1}'
  )"
  export DOCKAUTO_CONFIG_HASH="${config_hash}"

  # Source hash
  # tar all project except
  # .git, .dockauto, node_modules, tmp, log(s)
  # + user .dockautoignore
  local source_hash

  (
    cd "$project_root"
    local tar_args=(
      tar
      cf
      -
      .
      --exclude='./.git'
      --exclude='./.dockauto'
      --exclude='./node_modules'
      --exclude='./tmp'
      --exclude='./log'
      --exclude='./logs'
      --exclude='./.venv'
      --exclude='./dist'
      --exclude='./build'
      --exclude='./target'
    )
    if [[ -f ".dockautoignore" ]]; then
      tar_args+=(--exclude-from='.dockautoignore')
    fi
    "${tar_args[@]}" 2>/dev/null
  ) | eval "$sha_cmd" | awk '{print $1}' >"${project_root}/.dockauto/.source_hash.tmp"

  local source_hash
  source_hash="$(cat "${project_root}/.dockauto/.source_hash.tmp")"
  rm -f "${project_root}/.dockauto/.source_hash.tmp"

  export DOCKAUTO_SOURCE_HASH="${source_hash}"

  # Build hash = SHA256 (CONFIG_HASH + SOURCE_HASH)
  local build_hash
  build_hash="$(printf "%s%s" "${config_hash}" "${source_hash}" | eval "$sha_cmd" | awk '{print $1}')"
  export DOCKAUTO_BUILD_HASH="${build_hash}"
}

dockauto_hash_check_cache() {
  local project_root="${DOCKAUTO_PROJECT_ROOT:-$(pwd)}"
  local cache_file="${project_root}/.dockauto/cache.json"

  export DOCKAUTO_CACHE_HIT=0
  export DOCKAUTO_CACHE_ENTRY_JSON=""

  if [[ ! -f "$cache_file" ]]; then
    log_debug "Cache file not found: ${cache_file} (no cache)."
    return 0
  fi

  if ! jq '.' "$cache_file" >/dev/null 2>&1; then
    log_warn "Cache file ${cache_file} is invalid JSON. Ignoring cache."
    return 0
  fi

  local entry
  entry="$(jq -c --arg h "${DOCKAUTO_BUILD_HASH}" '.builds[$h]' "$cache_file" 2>/dev/null || true)"

  if [[ -n "$entry" && "$entry" != "null" ]]; then
    export DOCKAUTO_CACHE_HIT=1
    export DOCKAUTO_CACHE_ENTRY_JSON="${entry}"
    return 0
  fi
}

# ====== Helper: atomic cache update (Step 5) ======

dockauto_cache_update_build_entry() {
  local project_root="${DOCKAUTO_PROJECT_ROOT:-$(pwd)}"
  local cache_file="${project_root}/.dockauto/cache.json"
  local tmp_file="${cache_file}.tmp"
  local lock_file="${cache_file}.lock"
  # JSON object (not array)
  local build_entry_json="$1"

  if ! command -v jq >/dev/null 2>&1; then
    log_warn "jq not found; cannot update cache.json."
    return 0
  fi

  mkdir -p "${project_root}/.dockauto"

  if command -v flock >/dev/null 2>&1; then
    (
      flock 9 || true
      if [[ -f "$cache_file" ]]; then
        jq --arg h "${DOCKAUTO_BUILD_HASH}" --argjson entry "$build_entry_json" \
          '.builds |= (. // {}) | .builds[$h] = $entry' \
          "$cache_file" >"$tmp_file"
      else
        jq --arg h "${DOCKAUTO_BUILD_HASH}" --argjson entry "$build_entry_json" \
          -n '{builds:{}} | .builds[$h] = $entry' >"$tmp_file"
      fi
      mv "$tmp_file" "$cache_file"
    ) 9>"$lock_file"
  else
    log_warn "flock not found; updating cache.json without file lock."
    if [[ -f "$cache_file" ]]; then
      jq --arg h "${DOCKAUTO_BUILD_HASH}" --argjson entry "$build_entry_json" \
        '.builds |= (. // {}) | .builds[$h] = $entry' \
        "$cache_file" >"$tmp_file"
    else
      jq --arg h "${DOCKAUTO_BUILD_HASH}" --argjson entry "$build_entry_json" \
        -n '{builds:{}} | .builds[$h] = $entry' >"$tmp_file"
    fi
    mv "$tmp_file" "$cache_file"
  fi
}