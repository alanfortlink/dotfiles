if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='nvim'
else
  export EDITOR='nvim'
fi

[ -f /usr/local/etc/profile.d/autojump.sh ] && . /usr/local/etc/profile.d/autojump.sh
# source $(brew --prefix nvm)/nvm.sh

export JAVA_HOME="/Users/alansilva/code/jdk-20.jdk/Contents/Home"

export PATH="$PATH:/Users/alansilva/.cargo/bin"
export PATH="$PATH:/Users/alansilva/code/flutter/bin"
export PATH="$PATH:/Users/alansilva/Library/Android/sdk"
export PATH="$PATH:/Users/alansilva/Library/Android/sdk/cmdline-tools/latest/bin"
export PATH="$PATH:/Users/alansilva/Library/Android/sdk/platform-tools"
export PATH="$JAVA_HOME/bin:$PATH"

source ~/antigen.zsh

# Load the oh-my-zsh's library.
antigen use oh-my-zsh

# Bundles from the default repo (robbyrussell's oh-my-zsh).
antigen bundle git
antigen bundle heroku
antigen bundle pip
antigen bundle lein
antigen bundle autojump
antigen bundle command-not-found

# Syntax highlighting bundle.
antigen bundle zsh-users/zsh-syntax-highlighting

# Load the theme.
antigen theme robbyrussell

# Tell Antigen that you're done.
antigen apply

set -o vi

source ~/.aliases
