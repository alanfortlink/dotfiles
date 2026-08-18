# dotfiles

Personal config for nvim, tmux, herdr, bash, and the Hyprland desktop.

## Layout

The split is by portability, not by machine:

| dir | goes to | contents |
| --- | --- | --- |
| `config/` | `~/.config/<name>` | anything that runs anywhere: `nvim`, `tmux`, `herdr`, `ghostty`, `alacritty`, `kitty`, `wezterm`, `btop`, `fastfetch`, `lazygit`, `starship.toml`, `claude` |
| `bin/` | `~/.local/bin/<name>` | portable scripts: `tmux-navigator`, `tmux-kill-pane-confirm`, `herdr-setup`, `ask-claude`, `gif-captioner` |
| `pi/` | `~/.pi/agent/` | pi coding agent config + `extensions/<name>/` |
| `.bashrc` etc. | `~/` | shell dotfiles |
| `omarchy/` | `~/.config/`, `~/.local/bin/` | Hyprland/Wayland/Omarchy only — `hypr`, `waybar`, `walker`, `mako`, `swayosd`, and `bin/` (`hypr-*`, `session-*`, `voxtype-toggle`, the `omarchy-pkg-add` agent wrappers) |

Nothing outside `omarchy/` depends on Omarchy, so a machine that isn't running
it can take everything else as-is. `./sync` enforces that: it skips the
`omarchy/` tree entirely when `/usr/share/omarchy` is absent.

## Status

Active. Primary machine is `tank` (Arch + Hyprland + Omarchy); `deck` is a
Steam Deck running the same. The zsh files (`.zshrc`, `.zpreztorc`,
`antigen.zsh`), `.hammerspoon/` and `config/wezterm/` are from macOS setups —
inert on Linux, live if the repo is deployed on a Mac.

Remotes: `origin` (github.com/alanfortlink/dotfiles) and `deck` (self-hosted
Gitea on the Steam Deck).

## Sync

```
./sync
```

Idempotent, and one-way in the sense that matters: it symlinks the repo into
`$HOME`, so from then on editing a config in `$HOME` writes straight back here.
Anything real already at a target is moved aside as `<target>.pre-link-<ts>`,
never deleted. To add something new, copy it into the right dir once and re-run.

Two things are linked file-by-file rather than as a whole directory, because
the live directory also holds state that must stay local to the machine:

- `config/herdr/` — herdr keeps its sockets, logs and session history in
  `~/.config/herdr`. The `.link-files` marker triggers per-file linking.
- `pi/` — `~/.pi/agent/` also holds `auth.json`, `sessions/` and
  `models-store.json`.

## Notes

- **tmux** (`config/tmux/tmux.conf`) is self-contained — base settings inlined,
  no `source-file` out to a distro config. Linked at `~/.config/tmux/`; do not
  create a `~/.tmux.conf`, tmux would load both. The `ctrl+shift` direct layer
  mirrors herdr's keymap and needs a terminal that sends CSI-u; `prefix+<key>`
  works anywhere.
- **herdr** (`config/herdr/`) — `config.toml`, plugin configs under
  `plugins/config/<plugin>/`, and plugin sources as `plugins/<plugin>/SOURCE`
  (upstream url + ref) plus `*.patch` for local commits. `bin/herdr-setup`
  clones, patches and links them.
- **hypr-mux-\*** (`omarchy/bin/`) — ALT+hjkl / ALT+Z / ALT+W route into herdr
  or tmux panes (local, or over ssh / `herdr --remote`) and fall through to
  Hyprland. `hypr-mux-lib.sh` works out which mux the focused window is showing.
- **pi** — `web-tools` needs `npm install` in its dir; the `tsconfig.json` paths
  are editor-only.
- `rr` — tmux helper: send a command to every other pane in the current window.

## New machine

1. Clone somewhere (e.g. `~/repos/dotfiles`) and run `./sync`.
2. Runtime deps: `tmux`, `nvim` (lazy.nvim), `herdr`, `zoxide`, `fzf`,
   `starship`. `bin/tmux-navigator` needs bash 4+ (`mapfile`), so on macOS
   install Homebrew's bash and put it ahead of `/bin` on `PATH`.
3. `herdr-setup` to clone and link the herdr plugins.
4. tpm for tmux-resurrect: clone `tmux-plugins/tpm` into `~/.tmux/plugins/tpm`,
   then `prefix+I`.
5. On Arch/Omarchy, `packages.txt` lists the extra packages the `omarchy/`
   configs expect.
