#!/bin/bash

NVIM_HOME="$HOME/.config/nvim"
NVIM_LUA_HOME="$NVIM_HOME/after"

mkdir -p $NVIM_LUA_HOME

cp -R snippets $NVIM_HOME
cp lua/* $NVIM_LUA_HOME

PACKER_INSTALL_DIR="$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim"
[[ ! -d $PACKER_INSTALL_DIR ]] && git clone --depth 1 https://github.com/wbthomason/packer.nvim $PACKER_INSTALL_DIR
