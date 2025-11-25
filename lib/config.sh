#!/usr/bin/env bash
set -euo pipefail

# Trong Step 2 bạn sẽ dùng yq/jq để parse dockauto.yml
# Bây giờ chỉ log cho biết.

dockauto_config_load() {
  local config_file="$1"
  local profile="${2:-}"

  if [[ ! -f "$config_file" ]]; then
    log_error "Config file not found: ${config_file}"
    exit 1
  fi

  log_debug "Loading config from ${config_file} (profile=${profile:-default})"

  # TODO Step 2:
  # - dùng yq để parse x-dockauto.project, .services, ...
  # - lưu lại vào biến/global khác nếu cần
}

# Bạn có thể thêm stub helper, ví dụ:
dockauto_config_get_language() {
  # TODO dùng yq trong Step 2, giờ tạm return rỗng
  :
}
