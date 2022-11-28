#!/bin/bash

NVIM_HOME="$HOME/.config/nvim"
NVIM_LUA_HOME="$NVIM_HOME/lua"

mkdir -p $NVIM_LUA_HOME

cp -R snippets $NVIM_HOME
cp init.vim coc-settings.json $NVIM_HOME
cp lua/* $NVIM_LUA_HOME

PACKER_INSTALL_DIR="$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim"
# /COPILOT_INSTALL_DIR="$HOME/.config/nvim/pack/github/start/copilot.vim"

[[ ! -d $PACKER_INSTALL_DIR ]] && git clone --depth 1 https://github.com/wbthomason/packer.nvim $PACKER_INSTALL_DIR
