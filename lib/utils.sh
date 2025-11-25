#!/usr/bin/env bash
set -euo pipefail

# Basic color
_red='\033[0;31m'
_yellow='\033[0;33m'
_blue='\033[0;34m'
_green='\033[0;32m'
_reset='\033[0m'

log_info() {
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
