#!/usr/bin/env bash
set -euo pipefail

# ====== Step 6: Scan image (Trivy / SBOM) ======

dockauto_scan_image() {
  local image_tag="$1"

  if [[ "${DOCKAUTO_SCAN_AVAILABLE:-1}" -ne 1 ]]; then
    log_warn "Scan tools not available or --no-scan enabled; skipping scan for image ${image_tag}."
    return 0
  fi

  local project_root="${DOCKAUTO_PROJECT_ROOT:-$(pwd)}"

  # ----- Vulnerability scan -----
  if [[ "${DOCKAUTO_CFG_SECURITY_SCAN_ENABLED:-false}" == "true" ]]; then
    if [[ "${DOCKAUTO_CFG_SECURITY_SCAN_TOOL}" != "trivy" ]]; then
      log_warn "Only 'trivy' scan tool is supported currently; configured: ${DOCKAUTO_CFG_SECURITY_SCAN_TOOL}."
    else
      local outdir="${DOCKAUTO_CFG_SECURITY_SCAN_OUTPUT:-reports/security}"
      mkdir -p "${project_root}/${outdir}"
      local report_file="${project_root}/${outdir}/trivy-${DOCKAUTO_BUILD_HASH}.json"

      log_info "Running Trivy scan for image ${image_tag}..."
      if ! trivy image --quiet --format json --output "${report_file}" "${image_tag}"; then
        log_warn "Trivy scan command failed; check ${report_file} if it exists."
      else
        log_success "Trivy report written to ${report_file}"

        # Apply fail_on policy
        if [[ -n "${DOCKAUTO_CFG_SECURITY_SCAN_FAIL_ON:-}" ]]; then
          local severities_to_fail="${DOCKAUTO_CFG_SECURITY_SCAN_FAIL_ON}"
          IFS=',' read -r -a sev_arr <<<"${severities_to_fail}"
          local cond=""
          for s in "${sev_arr[@]}"; do
            local t
            t="$(echo "$s" | xargs)"
            [[ -z "$t" ]] && continue
            if [[ -n "$cond" ]]; then cond+=" or "; fi
            cond+="(.Severity == \"${t}\")"
          done

          if [[ -n "$cond" ]]; then
            local count
            count="$(jq -r "
              [ .Results[].Vulnerabilities[]? | select(${cond}) ] | length
            " "${report_file}" 2>/dev/null || echo "0")"

            if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
              log_error "Security scan found ${count} vulnerabilities with severities [${severities_to_fail}] in ${report_file}"
              return 1
            else
              log_success "No vulnerabilities found with severities [${severities_to_fail}]."
            fi
          fi
        fi
      fi
    fi
  else
    log_debug "Security.scan.enabled=false; skipping vulnerability scan."
  fi

  # ----- SBOM generation -----
  if [[ "${DOCKAUTO_CFG_SECURITY_SBOM_ENABLED:-false}" == "true" ]]; then
    if [[ "${DOCKAUTO_CFG_SECURITY_SBOM_TOOL}" != "syft" ]]; then
      log_warn "Only 'syft' SBOM tool is supported currently; configured: ${DOCKAUTO_CFG_SECURITY_SBOM_TOOL}."
    else
      local sbom_outdir="${DOCKAUTO_CFG_SECURITY_SBOM_OUTPUT:-reports/sbom}"
      mkdir -p "${project_root}/${sbom_outdir}"
      local format="${DOCKAUTO_CFG_SECURITY_SBOM_FORMAT:-spdx-json}"

      local ext="json"
      case "$format" in
        spdx-json) ext="spdx.json" ;;
        cyclonedx-json) ext="cdx.json" ;;
      esac

      local sbom_file="${project_root}/${sbom_outdir}/sbom-${DOCKAUTO_BUILD_HASH}.${ext}"

      log_info "Generating SBOM for image ${image_tag} with syft (${format})..."
      if ! syft packages "docker:${image_tag}" -o "${format}" >"${sbom_file}"; then
        log_warn "Syft command failed; SBOM may be incomplete."
      else
        log_success "SBOM written to ${sbom_file}"
      fi
    fi
  else
    log_debug "Security.sbom.enabled=false; skipping SBOM."
  fi
}
