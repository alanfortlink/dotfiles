#!/usr/bin/env bash
# Keep the $shortcut workspace token aligned with Herdr's current sidebar
# number. Lifecycle events can race with a close, so reconcile from a fresh
# snapshot up to three times and tolerate only a workspace proven to be gone.
set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
state_dir=${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/herdr-space-index}
source_id=herdr-space-index
max_attempts=3

mkdir -p "$state_dir"

# Event bursts must not interleave snapshots and publish stale positions.
exec 9>"$state_dir/space-index.lock"
flock 9

workspace_rows() {
  jq -r '
    if (.result.workspaces | type) != "array" then
      error("workspace list response has no workspaces array")
    else
      .result.workspaces[] |
      if ((.workspace_id | type) != "string") or
         ((.number != null) and
          (((.number | type) != "number") or (.number != (.number | floor))))
      then
        error("workspace list response contains an invalid workspace")
      else
        [.workspace_id, (.number // "")] | @tsv
      end
    end
  '
}

for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  listing=$("$herdr_bin" workspace list)
  rows=$(workspace_rows <<<"$listing")
  retry=0

  while IFS=$'\t' read -r workspace_id number; do
    [[ -n $workspace_id ]] || continue

    if [[ $number =~ ^[0-9]+$ ]] && ((number >= 1 && number <= 9)); then
      report_args=(--token "shortcut=$number")
    else
      report_args=(--clear-token shortcut)
    fi

    if "$herdr_bin" workspace report-metadata "$workspace_id" \
      --source "$source_id" "${report_args[@]}" >/dev/null
    then
      continue
    else
      report_status=$?
    fi

    # A close between list and report is expected. Confirm from another valid
    # snapshot; any other report failure is real and must fail the hook.
    current_listing=$("$herdr_bin" workspace list)
    current_rows=$(workspace_rows <<<"$current_listing")
    workspace_still_exists=0
    while IFS=$'\t' read -r current_id _; do
      if [[ $current_id == "$workspace_id" ]]; then
        workspace_still_exists=1
        break
      fi
    done <<<"$current_rows"

    if ((workspace_still_exists)); then
      printf 'herdr-space-index: metadata update failed for live workspace %s\n' \
        "$workspace_id" >&2
      exit "$report_status"
    fi

    retry=1
    break
  done <<<"$rows"

  ((retry == 0)) && exit 0
done

printf 'herdr-space-index: workspace set kept changing after %d attempts\n' \
  "$max_attempts" >&2
exit 1
