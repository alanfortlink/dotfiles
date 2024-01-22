#!/bin/bash

NVIM_HOME="$HOME/.config/nvim"
mkdir -p $NVIM_HOME

cp -R neovim/lua $NVIM_HOME
cp -R neovim/init.lua $NVIM_HOME
cp -R neovim/snippets $NVIM_HOME

PACKER_INSTALL_DIR="$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim"
[[ ! -d $PACKER_INSTALL_DIR ]] && git clone --depth 1 https://github.com/wbthomason/packer.nvim $PACKER_INSTALL_DIR
