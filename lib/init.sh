#!/usr/bin/env bash
set -euo pipefail

docker_cmd_init_help_usage() {
  cat <<'EOF'
Usage: dockauto init [--lang <node|python|java|...>] [--from-compose <file>] [--force]

Options:
  --lang LANG           Generate dockauto.yml from built-in template for language
  --from-compose FILE   Generate dockauto.yml from existing docker-compose.yml
  --force               Overwrite existing dockauto.yml if it exists

Examples:
  dockauto init --lang node
  dockauto init --lang python
  dockauto init --lang java
  dockauto init --from-compose docker-compose.yml
EOF
}

docker_cmd_init() {
  local lang=""
  local from_compose=""
  local force=0

  # Parse args for init
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lang)
        lang="${2:-}"
        shift 2
        ;;

      --from-compose)
        from_compose="${2:-}"
        shift 2
        ;;

      --force)
        force=1
        shift
        ;;

      -h|--help)
        docker_cmd_init_help_usage
        return 0
        ;;

      *)
        log_error "Unknown option for init: $1"
        docker_cmd_init_help_usage
        return 1
        ;;
    esac
  done

  # Check conflict
  if [[ -n "$lang" && -n "$from_compose" ]]; then
      log_error "Please use either --lang or --from-compose, not both."
      return 1
  fi

  if [[ -z "$lang" && -n "$from_compose" ]]; then
    dockauto_init_from_compose "$from_compose" "$force"
  elif [[ -n "$lang" && -z "$from_compose" ]]; then
    dockauto_init_from_lang "$lang" "$force"
  else
    log_error "You must specify either --lang or --from-compose."
    docker_cmd_init_help_usage
    return 1
  fi
}

dockauto_init_from_lang() {
  local lang="$1"
  local force="$2"
  local target_file="dockauto.yml"

  local template_file="${DOCKAUTO_ROOT_DIR}/templates/dockauto.${lang}.yml"

  if [[ ! -f "$template_file" ]]; then
    log_error "No template found for language '${lang}' at ${template_file}"
    return 1
  fi

  if [[ -f "$target_file" && "$force" -ne 1 ]]; then
    log_error "${target_file} already exists. Use --force to overwrite."
    return 1
  fi

  cp "$template_file" "$target_file"
  log_success "Generate ${target_file} from template '${lang}'."
  log_info "You can now edit ${target_file} to match your project."
}

dockauto_init_from_compose() {
  local compose_file="$1"
  local force="$2"
  local target_file="dockauto.yml"

  if [[ ! -f "$compose_file" ]]; then
    log_error "Compose file not found: ${compose_file}"
    return 1
  fi

  if [[ -f "$target_file" && "$force" -ne 1 ]]; then
    log_error "${target_file} already exists. Use --force to overwrite."
    return 1
  fi

  log_info "Generating ${target_file} from ${compose_file} ..."

  # Copy compose to dockauto.yml
  # Append x-dockauto skeleton (User custom)
  cp "$compose_file" "${target_file}"

  cat >>"$target_file" <<'EOF'

# ==== x-dockauto metadata (added by dockauto init --from-compose) ====
x-dockauto:
  project:
    name: my_app
    main_service: app
    language: node
    language_version: "22"

  build:
    lockfiles:
      - package-lock.json
    # dockerfile_template: node

  tests:
    enabled: true
    default_suites: ["unit"]
    suites:
      unit:
        cmd: "npm test"
        requires_infra: []
      integration:
        cmd: "npm run test:integration"
        requires_infra: ["db", "redis"]

  security:
    scan:
      enabled: true
      tool: trivy
      fail_on: ["CRITICAL","HIGH"]
      output: "reports/security"
    sbom:
      enabled: true
      tool: syft
      format: "spdx-json"
      output: "reports/sbom"

  profiles:
    dev:
      description: "Local development"
    ci:
      description: "CI pipeline build + full tests"

# NOTE:
# - Please review x-dockauto.project.language / tests / infra mapping.
# - Ensure 'main_service' matches your app service (e.g., 'app', 'web', etc.).
EOF

  log_success "Generated ${target_file} from ${compose_file}."
  log_info "Please review the added x-dockauto block at the end of ${target_file}."
}