# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source ~/.local/share/omarchy/default/bash/rc

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
