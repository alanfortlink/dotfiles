#!/bin/bash

NVIM_HOME="$HOME/.config/nvim"

rm -rf $HOME/.old.nvim
mv $NVIM_HOME $HOME/.old.nvim
mkdir -p $NVIM_HOME

cp -R after $NVIM_HOME
cp -R lua $NVIM_HOME
cp -R init.lua $NVIM_HOME
cp -R snippets $NVIM_HOME

cp -R $HOME/.old.nvim/undo $NVIM_HOME

PACKER_INSTALL_DIR="$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim"
[[ ! -d $PACKER_INSTALL_DIR ]] && git clone --depth 1 https://github.com/wbthomason/packer.nvim $PACKER_INSTALL_DIR
