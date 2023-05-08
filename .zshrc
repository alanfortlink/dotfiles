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
source $(brew --prefix nvm)/nvm.sh

export JAVA_HOME="/Users/alansilva/code/jdk-20.jdk/Contents/Home"

export PATH="$PATH:/Users/alansilva/.cargo/bin"
export PATH="$PATH:/Users/alansilva/code/flutter/bin"
export PATH="$PATH:/Users/alansilva/Library/Android/sdk"
export PATH="$PATH:/Users/alansilva/Library/Android/sdk/cmdline-tools/latest/bin"
export PATH="$PATH:/Users/alansilva/Library/Android/sdk/platform-tools"
export PATH="$JAVA_HOME/bin:$PATH"


