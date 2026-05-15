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

# Ctrl+P/Ctrl+N for history (emacs-style), in both vi keymaps.
bind -m vi-insert '"\C-p": previous-history'
bind -m vi-insert '"\C-n": next-history'
bind -m vi-command '"\C-p": previous-history'
bind -m vi-command '"\C-n": next-history'

# zoxide: autojump replacement. `j <substring>` to jump, `ji` for interactive fzf pick.
eval "$(zoxide init bash --cmd j)"
