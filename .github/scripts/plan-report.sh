#!/usr/bin/env bash
# Turns a captured `terraform plan` output into a markdown report and appends
# it to the job summary. Used by the plan workflow for every layer.
#
#   plan-report.sh <plan output file> <report file>
#
# Environment: ENVIRONMENT, LAYER, PLAN_OUTCOME (success|failure)
set -euo pipefail

plan_file="$1"
report_file="$2"

status_line=$(grep -E '^(Plan:|No changes\.|Error:)' "${plan_file}" | head -n 1 || true)
run_url=$(grep -Eo 'https://app\.terraform\.io/app/[^[:space:]]+' "${plan_file}" | head -n 1 || true)
if [ "${PLAN_OUTCOME}" = "success" ]; then icon="✅"; else icon="❌"; fi
: "${status_line:=Plan ${PLAN_OUTCOME}; see output below}"

# Keep each comment well under GitHub's 65,536 character limit.
trimmed=$(mktemp)
if [ "$(wc -c < "${plan_file}")" -gt 60000 ]; then
  head -c 60000 "${plan_file}" > "${trimmed}"
  printf '\n\n... output truncated; open the HCP Terraform run for the full plan.\n' >> "${trimmed}"
else
  cp "${plan_file}" "${trimmed}"
fi

{
  echo "<!-- terraform-plan:${ENVIRONMENT}:${LAYER} -->"
  echo "### ${icon} Terraform plan for \`${ENVIRONMENT}\` / \`${LAYER}\`"
  echo
  echo "**${status_line}**"
  if [ -n "${run_url}" ]; then
    echo
    echo "HCP Terraform run: ${run_url}"
  fi
  echo
  echo "<details><summary>Plan output</summary>"
  echo
  echo '```text'
  cat "${trimmed}"
  echo '```'
  echo
  echo "</details>"
  echo
  echo "_Commit ${GITHUB_SHA} · [workflow run](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID})_"
} > "${report_file}"

cat "${report_file}" >> "${GITHUB_STEP_SUMMARY}"
rm -f "${trimmed}"
