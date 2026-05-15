if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='nvim'
else
  export EDITOR='nvim'
fi

[ -f /usr/local/etc/profile.d/autojump.sh ] && . /usr/local/etc/profile.d/autojump.sh
# source $(brew --prefix nvm)/nvm.sh

export JAVA_HOME="/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"

export PATH="$PATH:/Users/alansilva/.cargo/bin"
export PATH="$PATH:/Users/alan/development/bin"
export PATH="$PATH:/Users/alan/development/flutter/bin"
export PATH="$PATH:/Users/alansilva/Library/Android/sdk"
export PATH="$PATH:/Users/alansilva/Library/Android/sdk/cmdline-tools/latest/bin"
export PATH="$PATH:/Users/alansilva/Library/Android/sdk/platform-tools"
export PATH="$JAVA_HOME/bin:$PATH"

source ~/antigen.zsh

# Load the oh-my-zsh's library.
antigen use oh-my-zsh

# Bundles from the default repo (robbyrussell's oh-my-zsh).
antigen bundle timer
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

# Vi-mode default kills Ctrl+L clear-screen; put it back in both keymaps.
bindkey -M viins '^L' clear-screen
bindkey -M vicmd '^L' clear-screen

# Ctrl+P/Ctrl+N for history (emacs-style), in both vi keymaps.
bindkey -M viins '^P' up-line-or-history
bindkey -M viins '^N' down-line-or-history
bindkey -M vicmd '^P' up-line-or-history
bindkey -M vicmd '^N' down-line-or-history

source ~/.aliases

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/alan/repos/quiz_server/temp/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/alan/repos/quiz_server/temp/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/alan/repos/quiz_server/temp/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/alan/repos/quiz_server/temp/google-cloud-sdk/completion.zsh.inc'; fi

source ~/.aliases
