export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="sorin"
plugins=(git vi-mode autojump)
source $ZSH/oh-my-zsh.sh

if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='nvim'
else
  export EDITOR='nvim'
fi

[ -f /usr/local/etc/profile.d/autojump.sh ] && . /usr/local/etc/profile.d/autojump.sh
source ~/.aliases
