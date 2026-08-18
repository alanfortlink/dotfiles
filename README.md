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
- `omarchy/tmux/tmux.conf` — Omarchy's tmux defaults (sourced from `/usr/share/omarchy`) + the herdr key layer (ctrl+shift direct keys, prefix+hjkl focus, `tmux-navigator` on prefix+g), herdr-matching theme, kill-pane confirmation when the pane is busy (`tmux-kill-pane-confirm`), tpm + resurrect. Linked to `~/.config/tmux/` so `omarchy restart/refresh tmux`, `omarchy-theme-set-tmux` and migrations keep working; no `~/.tmux.conf` (tmux would load both).
- `nvim/` — full `~/.config/nvim` mirror (init.lua, lua/, snippets, ftplugin, lazy-lock)
- `omarchy/` — mirror of `~/.config/<name>` for: `hypr`, `tmux`, `waybar`, `walker`, `mako`, `swayosd`, `ghostty`, `alacritty`, `kitty`, `btop`, `fastfetch`, `lazygit`, `starship.toml`
- `omarchy/bin/` — scripts from `~/.local/bin` (codex, copilot, gemini, ghui, opencode, session-save/restore, web-search, etc.)
- `omarchy/herdr/` — herdr `config.toml`, plugin configs (`plugins/config/<plugin>/`), and plugin sources (`plugins/<plugin>/SOURCE` = upstream url + ref, plus `*.patch` for local commits). Not dir-linked: `~/.config/herdr` holds the server's sockets/session state, so `.link-files` makes `sync-omarchy` link each tracked file individually. `herdr-setup` (in `omarchy/bin`) clones/patches/links the plugins.
- `omarchy/bin/hypr-mux-*` — ALT+hjkl / ALT+Z / ALT+W route into herdr or tmux panes (local, or over ssh / `herdr --remote`) and fall through to Hyprland; wired in `omarchy/hypr/bindings.lua`. `hypr-mux-lib.sh` resolves which mux the active window shows.
- `pi/` — pi coding agent: `settings.json`, `keybindings.json`, `APPEND_SYSTEM.md`, and `extensions/<name>/` (ask, claude-footer, compact-view, delegate, ollama-provider, web-tools). `sync-omarchy` links these into `~/.pi/agent/` individually (auth, sessions, models-store, and omarchy-managed extension/theme stay local). `web-tools` needs `npm install` in its dir; the `tsconfig.json` paths are editor-only.
- `claude/` — curated `~/.claude` subset: `CLAUDE.md`, `settings.json`, `skills/`, `agents/`, `commands/` (no secrets/sessions/history)
- `sync-omarchy` — the sync script
- `rr` — tmux helper: send a command to every other pane in the current window

## Install

No bootstrap script yet. To adopt on a new machine:

1. Clone the repo somewhere (e.g. `~/repos/dotfiles`).
2. Symlink or copy what you want into place. The layout mirrors the source:
   - `.bashrc`, `.aliases` → `~/`
   - `nvim/` → `~/.config/nvim/`
   - `omarchy/<name>/` → `~/.config/<name>/`
   - `omarchy/bin/<script>` → `~/.local/bin/<script>` (chmod +x)
   - `claude/` contents → `~/.claude/` (selective)
   - `pi/` → `~/.pi/agent/` (files + `extensions/<name>`; or just run `./sync-omarchy`)
3. Install runtime deps used by configs: `zoxide`, `tmux` + tpm, `nvim` (with lazy.nvim), starship, plus the omarchy-managed Hyprland stack.
4. herdr: install `herdr`, then run `herdr-setup` to clone + link the plugins listed in `omarchy/herdr/plugins/`.
5. From then on, run `./sync-omarchy` after editing live configs to pull changes back into the repo, then commit.
