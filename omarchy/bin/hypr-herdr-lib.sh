# shellcheck shell=bash
# Shared helpers for hypr-herdr-{focus,close,zoom}.
#
# Resolves which herdr server(s) the active Hyprland window is showing, in
# innermost-first order. Each entry is "local" or an ssh target. Cases:
#   ghostty -> herdr                       => local
#   ghostty -> ssh host (herdr inside)     => host
#   ghostty -> herdr --remote host         => host
#   ghostty -> herdr, focused pane running ssh host / herdr --remote host
#                                          => host, local   (cascade)

# From inside a herdr pane the CLI would resolve --current from HERDR_PANE_ID;
# we always want the server-focused pane (what the user is looking at).
unset HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID

HH_SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=3 -o LogLevel=ERROR
  -o ControlMaster=auto -o ControlPath="$HOME/.ssh/hypr-herdr-%C" -o ControlPersist=10m)
# Non-login remote shells often lack ~/.local/bin on PATH.
HH_REMOTE_PATH='PATH=$PATH:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin'

# hh <target> <herdr args...>  — run a herdr CLI command locally or over ssh.
hh() {
  local target=$1; shift
  if [[ $target == local ]]; then
    herdr "$@"
  else
    ssh "${HH_SSH_OPTS[@]}" "$target" "$HH_REMOTE_PATH herdr $(printf '%q ' "$@")"
  fi
}

# Extract the ssh destination from an argv (skips options that take a value).
_hh_ssh_target() {
  local -a argv=("$@")
  local i=1 a
  while (( i < ${#argv[@]} )); do
    a=${argv[i]}
    case $a in
      -[bcDEeFIiJLlmOopQRSWwB]) (( i += 2 )); continue ;;
      -[bcDEeFIiJLlmOopQRSWwB]*) (( i++ )); continue ;;
      -*) (( i++ )); continue ;;
      *) printf '%s' "$a"; return 0 ;;
    esac
  done
  return 1
}

# Extract host from `herdr --remote host` / `--remote=host` argv.
_hh_herdr_remote() {
  local -a argv=("$@")
  local i
  for (( i = 1; i < ${#argv[@]}; i++ )); do
    case ${argv[i]} in
      --remote) printf '%s' "${argv[i+1]:-}"; return 0 ;;
      --remote=*) printf '%s' "${argv[i]#--remote=}"; return 0 ;;
    esac
  done
  return 1
}

# Given a process name and argv, print the herdr target it implies (or nothing).
_hh_target_from_proc() {
  local name=$1; shift
  case $name in
    herdr) if r=$(_hh_herdr_remote "$@"); then printf '%s' "$r"; else printf 'local'; fi ;;
    ssh)   _hh_ssh_target "$@" ;;
    *)     return 1 ;;
  esac
}

# Sets HH_TARGETS (array, innermost first). Returns 1 if the active window
# hosts no herdr at all.
hh_resolve_targets() {
  HH_TARGETS=()
  local win_pid
  win_pid=$(hyprctl -j activewindow | jq -r '.pid // empty')
  [[ -n $win_pid ]] || return 1

  # Find herdr/ssh processes descending from the window pid; keep the
  # shallowest (herdr wins ties). Pane shells belong to the herdr *server*, so
  # they never appear under the window; nesting is handled via process-info.
  local p cur depth name best= best_depth=999999 best_name=
  for p in $(pgrep -x 'herdr|ssh'); do
    cur=$p; depth=0
    while [[ $cur -gt 1 ]]; do
      cur=$(awk '/^PPid:/{print $2}' /proc/$cur/status 2>/dev/null) || break
      [[ -z $cur ]] && break
      (( depth++ ))
      if [[ $cur == "$win_pid" ]]; then
        name=$(cat /proc/$p/comm)
        if (( depth < best_depth )) || { (( depth == best_depth )) && [[ $name == herdr && $best_name != herdr ]]; }; then
          best=$p; best_depth=$depth; best_name=$name
        fi
        break
      fi
    done
  done
  [[ -n $best ]] || return 1

  local -a argv
  mapfile -d '' -t argv < /proc/$best/cmdline
  local t
  t=$(_hh_target_from_proc "$best_name" "${argv[@]}") || return 1

  if [[ $t == local ]]; then
    # Nested: focused local pane may itself be an ssh / remote-herdr session.
    local fg_name fg_argv_json
    fg_name=$(herdr pane process-info --current 2>/dev/null \
      | jq -r '.result.process_info.foreground_processes[0].name // empty')
    if [[ $fg_name == ssh || $fg_name == herdr ]]; then
      mapfile -t argv < <(herdr pane process-info --current 2>/dev/null \
        | jq -r '.result.process_info.foreground_processes[0].argv[]')
      local inner
      inner=$(_hh_target_from_proc "$fg_name" "${argv[@]}") || inner=
      [[ -n $inner && $inner != local ]] && HH_TARGETS+=("$inner")
    fi
    HH_TARGETS+=(local)
  else
    HH_TARGETS+=("$t")
  fi
  return 0
}
