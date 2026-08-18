# shellcheck shell=bash
# Shared helpers for hypr-mux-{focus,close,zoom} and tmux-kill-pane-confirm:
# route Hyprland keys into the terminal multiplexer (herdr or tmux) shown by
# the active window, local or over ssh, and fall through to Hyprland when
# there is none.
#
# hh_resolve_targets sets HH_TARGETS, innermost first. Each entry is
# "<kind> <host> [<client>]": kind is herdr, tmux, or any (an ssh session
# whose remote mux is unknown, so both are tried); host is local or an ssh
# destination; client is the tmux client tty when known. Cases:
#   ghostty -> herdr                        => herdr local
#   ghostty -> tmux                         => tmux local /dev/pts/N
#   ghostty -> ssh host (mux inside)        => any host
#   ghostty -> herdr --remote host          => herdr host
#   ghostty -> herdr, focused pane running ssh host / herdr --remote host / tmux
#                                           => that, then herdr local (cascade)

# From inside a herdr pane the CLI would resolve --current from HERDR_PANE_ID;
# we always want the server-focused pane (what the user is looking at).
unset HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID

HH_SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=3 -o LogLevel=ERROR
  -o ControlMaster=auto -o ControlPath="$HOME/.ssh/hypr-mux-%C" -o ControlPersist=10m)
# Non-login remote shells often lack ~/.local/bin on PATH.
HH_REMOTE_PATH='PATH=$PATH:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin'

# Pane foreground commands that count as "idle": killing such a pane needs no
# confirmation, anything else (agent, editor, ...) does.
HH_SHELLS='^(bash|zsh|sh|dash|fish|nu)$'

# hh <host> <herdr args...>  — run a herdr CLI command locally or over ssh.
hh() {
  local host=$1; shift
  if [[ $host == local ]]; then
    herdr "$@"
  else
    ssh "${HH_SSH_OPTS[@]}" "$host" "$HH_REMOTE_PATH herdr $(printf '%q ' "$@")"
  fi
}

# ht <host> <tmux args...>  — run a tmux command locally or over ssh.
ht() {
  local host=$1; shift
  if [[ $host == local ]]; then
    tmux "$@"
  else
    ssh "${HH_SSH_OPTS[@]}" "$host" "$HH_REMOTE_PATH tmux $(printf '%q ' "$@")"
  fi
}

# ht_client <host> [<client>] — echo the tmux client tty to act on. Falls back
# to the most recently active client (the only way to pick one over ssh).
ht_client() {
  local host=$1 client=${2:-}
  if [[ -n $client ]]; then printf '%s' "$client"; return 0; fi
  client=$(ht "$host" list-clients -F '#{client_activity} #{client_tty}' 2>/dev/null \
    | sort -n | tail -1 | cut -d' ' -f2)
  [[ -n $client ]] && printf '%s' "$client"
}

# ht_pane <host> <client> — echo the pane id the client is looking at.
ht_pane() {
  ht "$1" display-message -c "$2" -p '#{pane_id}' 2>/dev/null
}

# ht_kill_pane <host> <client> <pane_id> — kill a pane; ask first (in the
# client's status line) when it is running something other than a shell.
ht_kill_pane() {
  local host=$1 client=$2 pane=$3 cmd
  cmd=$(ht "$host" display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null)
  if [[ -z $cmd || $cmd =~ $HH_SHELLS ]]; then
    ht "$host" kill-pane -t "$pane"
  else
    ht "$host" confirm-before -b -t "$client" -p "Kill pane running $cmd? (y/n)" "kill-pane -t $pane"
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

# Given a process name, pid and argv, print the target entry it implies.
_hh_target_from_proc() {
  local name=$1 pid=$2; shift 2
  local r
  case $name in
    herdr)
      if r=$(_hh_herdr_remote "$@"); then printf 'herdr %s' "$r"; else printf 'herdr local'; fi ;;
    tmux)
      # The client's tty is its stdin (only meaningful for a local pid).
      r=$(readlink "/proc/$pid/fd/0" 2>/dev/null)
      printf 'tmux local %s' "$r" ;;
    ssh)
      r=$(_hh_ssh_target "$@") || return 1
      printf 'any %s' "$r" ;;
    *) return 1 ;;
  esac
}

# Sets HH_TARGETS (array, innermost first). Returns 1 if the active window
# hosts no multiplexer at all.
hh_resolve_targets() {
  HH_TARGETS=()
  local win_pid
  win_pid=$(hyprctl -j activewindow | jq -r '.pid // empty')
  [[ -n $win_pid ]] || return 1

  # Find herdr/tmux-client/ssh processes descending from the window pid; keep
  # the shallowest (herdr wins ties). Pane shells belong to the herdr/tmux
  # *server*, so they never appear under the window; nesting is handled below.
  # A tmux client renames itself to "tmux: client (<socket>)", so match comm
  # by prefix rather than with pgrep -x.
  local p cur depth name best= best_depth=999999 best_name=
  for p in $(pgrep 'herdr|ssh|tmux'); do
    name=$(cat "/proc/$p/comm" 2>/dev/null) || continue
    case $name in
      herdr|ssh) ;;
      "tmux: client"*) name=tmux ;;
      *) continue ;;
    esac
    cur=$p; depth=0
    while [[ $cur -gt 1 ]]; do
      cur=$(awk '/^PPid:/{print $2}' /proc/$cur/status 2>/dev/null) || break
      [[ -z $cur ]] && break
      (( depth++ ))
      if [[ $cur == "$win_pid" ]]; then
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
  t=$(_hh_target_from_proc "$best_name" "$best" "${argv[@]}") || return 1

  if [[ $t == "herdr local" ]]; then
    # Nested: the focused local herdr pane may itself run ssh, a remote herdr,
    # or a tmux client.
    local info fg_name fg_pid inner
    info=$(herdr pane process-info --current 2>/dev/null)
    fg_name=$(jq -r '.result.process_info.foreground_processes[0].name // empty' <<<"$info")
    fg_pid=$(jq -r '.result.process_info.foreground_processes[0].pid // empty' <<<"$info")
    if [[ $fg_name == ssh || $fg_name == herdr || $fg_name == tmux ]]; then
      mapfile -t argv < <(jq -r '.result.process_info.foreground_processes[0].argv[]' <<<"$info")
      inner=$(_hh_target_from_proc "$fg_name" "$fg_pid" "${argv[@]}") || inner=
      [[ -n $inner && $inner != "herdr local" ]] && HH_TARGETS+=("$inner")
    fi
    HH_TARGETS+=("herdr local")
  else
    HH_TARGETS+=("$t")
  fi
  return 0
}
