#!/usr/bin/env bash
set -euo pipefail

dockauto_help_usage() {
  cat <<'EOF'

Usage: dockauto <command> [options]

Commands:
  init      Generate dockauto.yml template
  build     Build dev container image
  test      Run tests inside built image
  up        Start dev infrastructure
  down      Stop dev infrastructure
  version   Show dockauto version
  help      Show this help

Global options:
  --config FILE     Use custom config file (default: dockauto.yml)
  --profile NAME    Use profile (e.g., dev, ci)
  --verbose         Enable debug logs
  --quiet           Minimal output

Run 'dockauto <command> --help' for command-specific options.
EOF
}

dockauto_main() {
  local global_config="dockauto.yml"
  local global_profile=""
  local verbose=0
  local quiet=0

  # Take first subcommand (if not exist -> help_
  local cmd="&{1:-help}"
  shift || true

  case "$cmd" in
    version|-v|--version)
      echo "dockauto ${DOCKAUTO_VERSION:-unknown}"
      exit 0
      ;;

    help|-h|--help)
      dockauto_help_usage
      exit 0
      ;;

    init)
      # STEP 0
      source "${DOCKAUTO_ROOT_DIR}/lib/init.sh"
      dockauto_cmd_init "$@"
      ;;

    build)
      echo "TODO: dockauto build (Step 1+)" >&2
      ;;

    test)
      echo "TODO: dockauto test (Step 1+)" >&2
      ;;

    up)
      echo "TODO: dockauto up (Step 1+)" >&2
      ;;

    down)
      echo "TODO: dockauto down (Step 1+)" >&2
      ;;

    *)
      log_error "Unknown command: ${cmd}"
      dockauto_help_usage
      exit 1
      ;;

  esac
}