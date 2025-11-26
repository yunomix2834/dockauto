#!/usr/bin/env bash
set -euo pipefail

# ====== Setup: install helper tools (yq, jq, trivy, syft) ======

dockauto_cmd_setup_usage() {
  cat <<'EOF'
Usage: dockauto setup [options]

Install helper tools required by dockauto (yq, jq) and optional security tools
(Trivy, Syft) using the detected package manager.

Options:
  --only-core      Only install core tools (yq, jq)
  --only-security  Only install security tools (trivy, syft)
  -h, --help       Show this help

NOTE:
  - This command may use sudo and your system package manager (apt, dnf, yum, brew).
  - For Docker itself, please follow official installation docs.
EOF
}

dockauto_cmd_setup() {
  local only_core=0
  local only_security=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --only-core)
        only_core=1
        shift
        ;;
      --only-security)
        only_security=1
        shift
        ;;
      -h|--help)
        dockauto_cmd_setup_usage
        return 0
        ;;
      *)
        log_error "Unknown option for setup: $1"
        dockauto_cmd_setup_usage
        return 1
        ;;
    esac
  done

  if [[ "$only_core" -eq 1 && "$only_security" -eq 1 ]]; then
    log_error "Cannot use --only-core and --only-security together."
    return 1
  fi

  local pkg_mgr=""
  if command -v apt-get >/dev/null 2>&1; then
    pkg_mgr="apt"
  elif command -v dnf >/dev/null 2>&1; then
    pkg_mgr="dnf"
  elif command -v yum >/dev/null 2>&1; then
    pkg_mgr="yum"
  elif command -v brew >/dev/null 2>&1; then
    pkg_mgr="brew"
  else
    pkg_mgr="unknown"
  fi

  log_info "Detected package manager: ${pkg_mgr}"

  # ---- Helper for core tools (yq, jq) ----
  dockauto_install_core_tools() {
    case "$pkg_mgr" in
      apt)
        log_info "Installing jq, yq via apt..."
        sudo apt-get update
        sudo apt-get install -y jq yq
        ;;
      dnf|yum)
        log_info "Installing jq, yq via ${pkg_mgr}..."
        sudo ${pkg_mgr} install -y jq yq
        ;;
      brew)
        log_info "Installing jq, yq via brew..."
        brew install jq yq
        ;;
      *)
        log_warn "Unsupported package manager; please install jq, yq manually."
        ;;
    esac
  }

  # ---- Helper for security tools (trivy, syft) ----
  dockauto_install_security_tools() {
    # Trivy
    if ! command -v trivy >/dev/null 2>&1; then
      log_info "Installing Trivy via upstream install script..."
      if command -v curl >/dev/null 2>&1; then
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
          | sudo sh -s -- -b /usr/local/bin
      else
        log_warn "curl not found; please install Trivy manually: https://aquasecurity.github.io/trivy/"
      fi
    else
      log_info "Trivy already installed."
    fi

    # Syft
    if ! command -v syft >/dev/null 2>&1; then
      log_info "Installing Syft via upstream install script..."
      if command -v curl >/dev/null 2>&1; then
        curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
          | sudo sh -s -- -b /usr/local/bin
      else
        log_warn "curl not found; please install Syft manually: https://github.com/anchore/syft"
      fi
    else
      log_info "Syft already installed."
    fi
  }

  if [[ "$only_core" -eq 1 ]]; then
    dockauto_install_core_tools
  elif [[ "$only_security" -eq 1 ]]; then
    dockauto_install_security_tools
  else
    dockauto_install_core_tools
    dockauto_install_security_tools
  fi

  log_success "Setup completed (some steps may have printed warnings if tools already installed or package manager unsupported)."
}
