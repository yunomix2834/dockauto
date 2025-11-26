#!/usr/bin/env bash
set -euo pipefail

# ====== Step 1: CLI + parse arguments & dispatch commands ======

dockauto_usage() {
  cat <<'EOF'

Usage: dockauto [global options] <command> [command options]

Commands:
  init      Generate dockauto.yml template
  build     Build dev container image
  test      Run tests inside built image
  up        Start dev infrastructure
  down      Stop dev infrastructure
  setup     Install helper tools (yq, jq, trivy, syft, ...)
  version   Show dockauto version
  help      Show this help

Global options:
  --config FILE     Use custom config file (default: dockauto.yml)
  --profile NAME    Use profile (e.g., dev, ci)
  --verbose         Enable debug logs
  --quiet           Minimal output

Examples:
  dockauto init --lang node
  dockauto build --skip-test --no-scan
  dockauto test --test integration
  dockauto up --keep-infra
  dockauto setup

EOF
}

dockauto_main() {
  local global_config="dockauto.yml"
  local global_profile=""
  local verbose=0
  local quiet=0

  local cmd=""

  # ====== Step 1: Parse global flags ======
  # Parse global flags
  # Only before sub-command
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        global_config="${2:-}"
        shift 2
        ;;
      --profile)
        global_profile="${2:-}"
        shift 2
        ;;
      --verbose)
        verbose=1
        shift
        ;;
      --quiet)
        quiet=1
        shift
        ;;
      help|-h|--help|version|-v|--version|init|build|test|up|down)
        cmd="$1"
        shift
        break
        ;;
      *)
        log_error "Unknown global option or command: $1"
        dockauto_usage
        exit 1
        ;;
    esac
  done

  # Set default cmd if not exist -> show help
  if [[ -z "${cmd}" ]]; then
    cmd="help"
  fi

  # Export global context for lib usage
  export DOCKAUTO_CONFIG_FILE="${global_config}"
  export DOCKAUTO_PROFILE="${global_profile}"
  export DOCKAUTO_VERBOSE="${verbose}"
  export DOCKAUTO_QUIET="${quiet}"

  log_debug "Global config file: ${DOCKAUTO_CONFIG_FILE}"
  log_debug "Global profile: ${DOCKAUTO_PROFILE}"
  log_debug "Verbose: ${DOCKAUTO_VERBOSE}, Quiet: ${DOCKAUTO_QUIET}"
  log_debug "Project root: ${DOCKAUTO_PROJECT_ROOT:-$(pwd)}"

  case "$cmd" in
    version|-v|--version)
      echo "dockauto ${DOCKAUTO_VERSION:-unknown}"
      exit 0
      ;;

    help|-h|--help)
      dockauto_usage
      exit 0
      ;;

    init)
      # Step 0: generate template
      source "${DOCKAUTO_ROOT_DIR}/lib/init.sh"
      dockauto_cmd_init "$@"
      ;;

    build)
      # Step 1: parse build flags + pipeline
      source "${DOCKAUTO_ROOT_DIR}/lib/build.sh"
      dockauto_cmd_build "$@"
      ;;

    test)
      source "${DOCKAUTO_ROOT_DIR}/lib/test.sh"
      dockauto_cmd_test "$@"
      ;;

    up)
      source "${DOCKAUTO_ROOT_DIR}/lib/infra.sh"
      dockauto_cmd_up "$@"
      ;;

    down)
      source "${DOCKAUTO_ROOT_DIR}/lib/infra.sh"
      dockauto_cmd_down "$@"
      ;;

    setup)
      source "${DOCKAUTO_ROOT_DIR}/lib/setup.sh"
      dockauto_cmd_setup "$@"
      ;;

    *)
      log_error "Unknown command: ${cmd}"
      dockauto_usage
      exit 1
      ;;
  esac
}