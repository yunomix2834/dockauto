#!/usr/bin/env bash
set -euo pipefail

# ====== DOCKAUTO CONTEXT (single source of truth) ======

# Defaults
: "${DOCKAUTO_CONFIG_FILE:=dockauto.yml}"
: "${DOCKAUTO_PROFILE:=}"
: "${DOCKAUTO_VERBOSE:=0}"
: "${DOCKAUTO_QUIET:=0}"

dockauto_ctx_init() {
  if [[ -z "${DOCKAUTO_PROJECT_ROOT:-}" ]]; then
    DOCKAUTO_PROJECT_ROOT="$(pwd)"
  fi
}

dockauto_ctx_set_globals() {
  local config="$1"
  local profile="$2"
  local verbose="$3"
  local quiet="$4"

  DOCKAUTO_CONFIG_FILE="$config"
  DOCKAUTO_PROFILE="$profile"
  DOCKAUTO_VERBOSE="$verbose"
  DOCKAUTO_QUIET="$quiet"
}

# Sub-process needs
dockauto_ctx_export_for_child() {
  export DOCKAUTO_CONFIG_FILE
  export DOCKAUTO_PROFILE
  export DOCKAUTO_PROJECT_ROOT
  export DOCKAUTO_VERSION
}