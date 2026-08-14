# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
# /etc/omarchy.conf is written by omarchy-dev-link. When absent, force the
# package default instead of preserving a stale inherited dev-link value before
# we decide which rc file to source.
if [[ -f /etc/omarchy.conf ]]; then
  source /etc/omarchy.conf
  export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
else
  export OMARCHY_PATH=/usr/share/omarchy
fi
source "$OMARCHY_PATH/default/bash/rc"

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'

[ -f ~/.aliases ] && source ~/.aliases

# Vi mode for command-line editing (Esc -> normal mode, i -> insert mode)
set -o vi

# Vi-mode default kills Ctrl+L clear-screen; put it back in both keymaps.
bind -m vi-insert '"\C-l": clear-screen'
bind -m vi-command '"\C-l": clear-screen'

# Ctrl+P/Ctrl+N: prefix-search history (matches what's typed before the cursor).
bind -m vi-insert '"\C-p": history-search-backward'
bind -m vi-insert '"\C-n": history-search-forward'
bind -m vi-command '"\C-p": history-search-backward'
bind -m vi-command '"\C-n": history-search-forward'

# zoxide: autojump replacement. `j <substring>` to jump, `ji` for interactive fzf pick.
eval "$(zoxide init bash --cmd j)"

# Unlimited shell history. -1 disables truncation in bash >= 4.3.
HISTSIZE=-1
HISTFILESIZE=-1
HISTTIMEFORMAT='%F %T  '
# Flush each command to disk immediately so nothing is lost on crash/poweroff.
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# Go binaries on PATH. Mirrors the export in ~/.zshrc (which only runs on the
# Mac); on Linux the shell is bash, so .zshrc is never sourced. Guarded so a
# missing dir doesn't pollute PATH — these only take effect once go is installed.
for _godir in "$HOME/.local/go/bin" "$HOME/go/bin"; do
  [ -d "$_godir" ] && PATH="$PATH:$_godir"
done
unset _godir
export PATH

# fzf: use fd (respects .gitignore, includes dotfiles) and bat previews.
if command -v fd &> /dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi
command -v bat &> /dev/null && export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always {}'"

export PATH="$PATH:/home/tank/.local/bin/go/bin/"

# leetcode TUI
export PATH="$HOME/.local/bin/leetcode/bin:$PATH"
export PATH="$HOME/flutter/bin:$PATH"
