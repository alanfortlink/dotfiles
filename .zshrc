# Homebrew (macOS). Login shells also get this from ~/.zprofile, but tmux/herdr
# panes are non-login shells, so it has to happen here too. No-op on Linux.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# ~/.local/bin: the repo's bin/ scripts and the claude launcher.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac

# Optional per-machine tool dirs; only added when they exist.
for _d in "$HOME/.local/go/bin" "$HOME/go/bin" "$HOME/.cargo/bin" "$HOME/.lmstudio/bin"; do
  [ -d "$_d" ] || continue
  case ":$PATH:" in *":$_d:"*) ;; *) PATH="$PATH:$_d" ;; esac
done
unset _d
export PATH

export EDITOR='nvim'

[ -f /usr/local/etc/profile.d/autojump.sh ] && . /usr/local/etc/profile.d/autojump.sh

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

# Ctrl+P/Ctrl+N: prefix-search history with what's typed before the cursor.
autoload -Uz history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end
bindkey -M viins '^P' history-beginning-search-backward-end
bindkey -M viins '^N' history-beginning-search-forward-end
bindkey -M vicmd '^P' history-beginning-search-backward-end
bindkey -M vicmd '^N' history-beginning-search-forward-end

source ~/.aliases

# Ollama host is per-machine; keep it out of the repo by putting the URL in ~/.config/ollama_host
[ -f "$HOME/.config/ollama_host" ] && export OLLAMA_HOST="$(<"$HOME/.config/ollama_host")"

# Starship prompt (hostname etc. via starship.toml); no-op if starship isn't installed.
if (( $+commands[starship] )) && [[ -z $STARSHIP_SHELL ]]; then
  eval "$(starship init zsh)"
fi
