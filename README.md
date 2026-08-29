# dotfiles (v2, chezmoi)

Chezmoi-managed dotfiles for zsh, tmux, neovim, herdr, and git. The repo root
**is** the chezmoi source state — no `sync` script, no symlinks; chezmoi copies
(and templates) files into `$HOME`.

Machines: `tank` / `deck` / `link` (Arch Linux), `macw` (macOS). OS-specific
behavior lives in templates (`.chezmoi.os`, `.chezmoi.homeDir`); nothing is
hardcoded per user.

## Deploy on a new machine

Prereqs: `zsh`, `tmux`, `nvim`, `git`; on macOS also Homebrew in
`/opt/homebrew`.

```sh
chezmoi init --apply <your-repo-url> --branch v2
```

`--branch v2` is the clean way; a URL fragment works too:

```sh
chezmoi init --apply '<your-repo-url>#v2'
```

If the branch was somehow not checked out after init:

```sh
chezmoi init <your-repo-url>
chezmoi cd   # then: git checkout v2; exit
chezmoi apply
```

## Branches

**`v2` is the active branch** (fresh orphan history, standard chezmoi layout).
The legacy branch mirrors the old `~/repos/dotfiles` layout driven by `./sync`.

## What's managed

| source | target |
| --- | --- |
| `dot_zshrc.tmpl`, `dot_aliases`, `dot_zpreztorc`, `dot_antigen.zsh` | `~/.zshrc`, `~/.aliases`, `~/.zpreztorc`, `~/antigen.zsh` |
| `dot_gitconfig` | `~/.gitconfig` |
| `dot_config/tmux/` | `~/.config/tmux/` |
| `dot_config/nvim/` | `~/.config/nvim/` |
| `dot_config/herdr/…` (selected files) | `~/.config/herdr/…` |

Notes:

- `antigen.zsh` is managed as `~/antigen.zsh`; `.zshrc` sources it from there.
- `~/.config/herdr` also holds machine-local runtime state (logs,
  `session.json`) that is *not* managed — only config files and the
  `herdr-navigator` plugin (SOURCE + patch) are.
- `~/.config/nvim/.luarc.json` is intentionally unmanaged (editor-local).
