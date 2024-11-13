#!/bin/bash

NVIM_HOME="$HOME/.config/nvim"
mkdir -p $NVIM_HOME
rm -rf $NVIM_HOME/*
rm -rf $HOME/.local/share/nvim

cp -R nvim/lua $NVIM_HOME
cp -R nvim/init.lua $NVIM_HOME
cp -R nvim/snippets $NVIM_HOME
