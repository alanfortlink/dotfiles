# dotfiles

Personal config for nvim, tmux, bash, ghostty, and omarchy (Hyprland).

## Status

Active. Targets two machines, both running omarchy (Arch + Hyprland):

- `tank` — primary omarchy desktop
- `deck` — Steam Deck running omarchy

Shell is bash. The zsh files (`.zshrc`, `.zpreztorc`, `antigen.zsh`) and `.hammerspoon/`, `wezterm/` are inert leftovers from prior macOS/zsh setups, kept for reference.

Sync is one-way: live system → repo, via `./sync-omarchy`. Self-discovering — anything already tracked gets refreshed; to add something new, copy it in once.

Remotes: `origin` (github.com/alanfortlink/dotfiles) and `deck` (self-hosted Gitea on the Steam Deck).

## What's inside

- `.bashrc`, `.aliases` — bash setup, vi mode, zoxide, unlimited history, git aliases
- `.tmux.conf` — vim-style panes, Alt-prefix bindings, dracula theme, tpm + resurrect
- `nvim/` — full `~/.config/nvim` mirror (init.lua, lua/, snippets, ftplugin, lazy-lock)
- `omarchy/` — mirror of `~/.config/<name>` for: `hypr`, `waybar`, `walker`, `mako`, `swayosd`, `ghostty`, `alacritty`, `kitty`, `btop`, `fastfetch`, `lazygit`, `starship.toml`
- `omarchy/bin/` — scripts from `~/.local/bin` (codex, copilot, gemini, ghui, opencode, session-save/restore, web-search, etc.)
- `claude/` — curated `~/.claude` subset: `CLAUDE.md`, `settings.json`, `skills/`, `agents/`, `commands/` (no secrets/sessions/history)
- `sync-omarchy` — the sync script
- `rr` — tmux helper: send a command to every other pane in the current window

## Install

No bootstrap script yet. To adopt on a new machine:

1. Clone the repo somewhere (e.g. `~/repos/dotfiles`).
2. Symlink or copy what you want into place. The layout mirrors the source:
   - `.bashrc`, `.aliases`, `.tmux.conf` → `~/`
   - `nvim/` → `~/.config/nvim/`
   - `omarchy/<name>/` → `~/.config/<name>/`
   - `omarchy/bin/<script>` → `~/.local/bin/<script>` (chmod +x)
   - `claude/` contents → `~/.claude/` (selective)
3. Install runtime deps used by configs: `zoxide`, `tmux` + tpm, `nvim` (with lazy.nvim), starship, plus the omarchy-managed Hyprland stack.
4. From then on, run `./sync-omarchy` after editing live configs to pull changes back into the repo, then commit.
