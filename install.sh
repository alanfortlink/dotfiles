#!/bin/bash

HOME="/home/thomas"

Install programs
curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
sudo apt install -y nodejs pip fzf ripgrep

sudo npm install -g yarn prettier

python3 -m pip install neovim

cp .tmux.conf .zshrc .personal $HOME
sh install_vim.sh

# Install nvm
curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash

# Setup node
nvm install 16.15
nvm use 16.15
npm install -g yarn

# Install packer
TMUX_PLUGIN_MANAGER_INSTALL_DIR="$HOME/.tmux/plugins/tpm"
[[ ! -d $TMUX_PLUGIN_MANAGER_INSTALL_DIR ]] && git clone https://github.com/tmux-plugins/tpm $TMUX_PLUGIN_MANAGER_INSTALL_DIR
