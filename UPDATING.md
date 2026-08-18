# Updating another machine from this repo

Runbook for an agent. Target machine: Omarchy/Arch with Hyprland. Run every
command on the **target** machine. Stop and report if a step fails; do not
improvise around a failure.

## 0. Locate the repo

```bash
REPO=$(find ~ -maxdepth 3 -type d -name .git -path '*dotfiles*' 2>/dev/null | head -1 | xargs -r dirname)
echo "${REPO:-NOT FOUND}"
```

If not found, clone it: `git clone https://github.com/alanfortlink/dotfiles.git ~/repos/dotfiles`
and set `REPO=~/repos/dotfiles`.

## 1. Pull

```bash
cd "$REPO"
git status --porcelain          # must be clean
git pull --ff-only origin main
```

If the tree is **not** clean, stop and show the diff — those are live edits made
through the symlinks and they belong to the user, not to you. Do not stash or
discard them.

The `deck` remote (`steamdeck.tail6bf4dc.ts.net:3000`) is a Tailscale-only Gitea
mirror; it is often offline. `origin` (GitHub) is authoritative.

## 2. Dependencies

```bash
sudo pacman -S --needed herdr tmux fzf jq playerctl nvtop tailscale voxtype-bin
paru -S --needed vicinae     # or yay
```

`herdr` and `voxtype-bin` come from the Omarchy repo. `fzf` + `jq` are what
`tmux-navigator` and `hypr-mux-lib.sh` shell out to. See `packages.txt` for why
each is here.

tmux plugin manager (tmux-resurrect is loaded from `omarchy/tmux/tmux.conf`):

```bash
[ -d ~/.tmux/plugins/tpm ] || git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

## 3. Link everything

```bash
"$REPO"/sync-omarchy
```

This is the only sync script to run. It is idempotent and it:

- links `omarchy/<name>` → `~/.config/<name>` (hypr, tmux, herdr, ghostty,
  alacritty, kitty, waybar, walker, mako, …)
- links `omarchy/bin/*` → `~/.local/bin/*` (`hypr-mux-*`, `tmux-navigator`,
  `tmux-kill-pane-confirm`, `herdr-setup`, …)
- links `pi/*` and `pi/extensions/*` into `~/.pi/agent/` file-by-file, leaving
  `auth.json`, `sessions/`, `models-store/` and omarchy-managed extensions local
- treats `omarchy/herdr/` specially (it has a `.link-files` marker): the live
  `~/.config/herdr` dir keeps herdr's sockets/logs/session state, so each tracked
  file is linked into it individually rather than replacing the dir

Anything real it displaces is moved to `<target>.pre-link-<ts>` — those are
gitignored; delete them once you have confirmed nothing was lost.

Ignore `sync-dotfiles`; it is the older home-directory-oriented script and
`sync-omarchy` supersedes it.

### Clean up stale herdr symlinks

Because herdr is linked per-file, files deleted from the repo leave dangling
links behind:

```bash
find ~/.config/herdr -xtype l -delete
```

## 4. herdr plugins

```bash
"$REPO"/omarchy/bin/herdr-setup
```

Clones each `omarchy/herdr/plugins/<name>/SOURCE` repo to `~/repos/<name>`,
checks out the pinned ref on a `local` branch, applies the `*.patch` files, and
`herdr plugin link`s it. Currently: `herdr-navigator` at `v0.3.6` + one keymap
patch (ctrl+j/k and ctrl+n/p move the selection).

## 5. pi extensions

`web-tools` has npm deps; the rest are dependency-free TypeScript:

```bash
cd "$REPO"/pi/extensions/web-tools && npm install
```

`pi/models.json` points the `lmstudio` provider at `http://10.0.0.75:1234/v1`
and `.bashrc` sets `OLLAMA_HOST=http://10.0.0.75:11434`. Both are the Mac on
the LAN — if the target machine is not on that LAN, expect those providers to
fail; leave the config as-is and mention it in your report.

## 6. Reload

```bash
hyprctl reload
omarchy-restart-waybar 2>/dev/null || true
tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null || true
herdr server reload-config 2>/dev/null || true
```

Then, in tmux, press `prefix + I` once to let tpm install tmux-resurrect.
A relogin is the safest way to pick up `~/.bashrc` and the Hyprland autostart
changes.

## 7. Verify

```bash
readlink -f ~/.config/hypr ~/.config/tmux ~/.config/herdr/config.toml ~/.pi/agent/settings.json
ls -l ~/.local/bin/hypr-mux-* ~/.local/bin/tmux-navigator
find ~/.config ~/.local/bin ~/.pi -xtype l 2>/dev/null   # must print nothing
hyprctl monitors >/dev/null && echo "hyprland ok"
tmux new -d -s _check && tmux kill-session -t _check && echo "tmux ok"
herdr plugin list
```

Then check by hand:

- ALT+h/j/k/l moves between herdr **and** tmux panes and falls through to
  Hyprland windows at the edges (`hypr-mux-lib.sh` decides which mux the focused
  window is showing).
- ALT+g opens the herdr session navigator; `prefix+g` opens `tmux-navigator`.
- `prefix+x` on a busy pane asks for confirmation.

## What changed in this batch

- `tmux`: config moved out of `~/.tmux.conf` into `omarchy/tmux/tmux.conf` →
  `~/.config/tmux/`. **Delete any `~/.tmux.conf` on the target** — tmux loads
  both and the config would double up.
- `herdr`: `hypr-herdr-*` scripts renamed to `hypr-mux-*` and taught to drive
  tmux as well; new `hypr-mux-split` / `hypr-mux-tab`; `alt+g` added to `goto`;
  `confirm_close = true`; UI sound off. Remove stale
  `~/.local/bin/hypr-herdr-*` on the target.
- `hypr`: `layout.lua` rewritten; `layout.json` and `layout-rules.conf` deleted
  in favour of `layout-rules.lua` / `layout-overrides.lua` / `layout-data.lua`.
  See `omarchy/hypr/layout.md`.
- `pi`: new `lmstudio-provider` extension and `models.json`; compact-view now
  renders the current activity in pi's Working spinner row.
