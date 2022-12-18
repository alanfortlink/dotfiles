#!/bin/bash

NVIM_HOME="$HOME/.config/nvim"
NVIM_LUA_HOME="$NVIM_HOME/lua"

mkdir -p $NVIM_LUA_HOME

cp init.lua $NVIM_HOME
cp -R snippets $NVIM_HOME
cp -R lua/* $NVIM_LUA_HOME

PACKER_INSTALL_DIR="$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim"
[[ ! -d $PACKER_INSTALL_DIR ]] && git clone --depth 1 https://github.com/wbthomason/packer.nvim $PACKER_INSTALL_DIR
