#!/usr/bin/env bash
set -euo pipefail

# ====== Common utils: logging, colors ======

# Basic color
_red='\033[0;31m'
_yellow='\033[0;33m'
_blue='\033[0;34m'
_green='\033[0;32m'
_reset='\033[0m'

# Set DOCKAUTO_VERBOSE, DOCKAUTO_QUIET in cli
log_debug() {
  if [[ "${DOCKAUTO_VERBOSE:-0}" -eq 1 ]]; then
    _now() { date +"%Y-%m-%d %H:%M:%S"; }
    printf "${_blue}[$(_now) DEBUG]${_reset} %s\n" "$*" >&2
  fi
}

log_info() {
  if [[ "${DOCKAUTO_QUIET:-0}" -eq 1 ]]; then
    return 0
  fi
  printf "${_blue}[INFO]${_reset} %s\n" "$*" >&2
}

log_warn() {
  printf "${_yellow}[WARN]${_reset} %s\n" "$*" >&2
}

log_error() {
  printf "${_red}[ERROR]${_reset} %s\n" "$*" >&2
}

log_success() {
  printf "${_green}[OK]${_reset} %s\n" "$*" >&2
}
