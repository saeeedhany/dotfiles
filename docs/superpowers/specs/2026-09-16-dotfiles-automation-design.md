# ThePrimeSetup.conf — Automated Bootstrap Design

**Date:** 2026-09-16
**Status:** Approved, pending implementation

## Problem

The repo cannot reproduce the machine it claims to describe.

`install.sh` targets a repo layout that does not exist. It clones
`github.com/saeeedhany/dotfiles` (a different repo) into `~/.dotfiles`, then
looks for `$DOTFILES/.config/nvim`, `$DOTFILES/suckless/`, `$DOTFILES/bin/`,
and root-level `.bashrc`, `.bash_profile`, `.profile`, `.xinitrc`,
`.Xresources`. None of these paths exist here. The real layout is `nvim/`,
`bash/bashrc`, `xdots/xinirc`. Run today the script installs packages, hits
`warn "... skipping"` on every config step, and prints "done."

Worse, the window manager is absent. `dwm`, `st`, and `dmenu` live on the
machine at `~/.config/suckless/` as git clones carrying custom
`config.def.h` files and four applied dwm patches. The repo contains only
`stColor/Gruvbox`, a 41-line fragment of st's `colorname[]` array. A fresh
clone gives you no window manager, no terminal, and no launcher.

`dwmblocks` is worse still: its source exists nowhere. Only
`/usr/local/bin/dwmblocks` and `~/.config/dwmblocks/scripts/` survive.

## Goals

1. `git clone && ./install.sh` reproduces this desktop on a fresh Arch box.
2. Configuration drift becomes structurally impossible, not merely discouraged.
3. The installer reports honest failure instead of silently skipping work.

## Non-goals

- Distro portability. The current script pretends to support Debian and
  Fedora but has no suckless build path for either. Arch only.
- Slimming the 67 MB wallpaper set. Explicitly kept at the user's direction.
- Rewriting `index.html` (the GitHub Pages site). Only its advertised
  install URL is wrong and gets corrected.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Suckless sources | Vendor full trees | No network, no patch conflicts, byte-exact |
| Conflict resolution | Machine wins | The live setup works and is newer nearly everywhere |
| Config placement | Symlink | Drift cannot recur; edits land in git immediately |
| Packages | Curated **and** full snapshot | Curated by default, snapshot for exact cloning |
| Hardware bits | Conditional guards | Monitor and GPU specifics must not break another box |
| dwmblocks | Reconstruct from binary | Otherwise permanently lost |

## Target layout

```
ThePrimeSetup.conf/
├── install.sh                  # orchestrator
├── sync.sh                     # machine -> repo, for non-symlinked paths
├── lib/
│   ├── log.sh                  # colors, log/info/warn/die/ok
│   ├── pkg.sh                  # pacman + yay bootstrap and install
│   └── link.sh                 # declarative link map, backup, verify
├── packages/
│   ├── pacman.txt              # curated native
│   ├── aur.txt                 # curated AUR
│   └── snapshot.txt            # full -Qqen + -Qqem dump (--full / record)
├── suckless/                   # symlinked to ~/.config/suckless
│   ├── dwm/                    # + patches/, config.def.h
│   ├── st/
│   ├── dmenu/
│   └── dwmblocks/              # reconstructed blocks.def.h
├── config/                     # each entry -> ~/.config/<name>
│   ├── nvim/  tmux/  dunst/  picom/  sxhkd/  zathura/
│   └── dwmblocks/scripts/
├── home/                       # -> ~/<dotfile>
│   ├── bashrc  bash_profile  xinitrc  xprofile
├── bin/                        # -> ~/.local/bin
│   ├── battery-monitor.sh  deasy  study/
├── Wallpapers/                 # -> ~/Pictures/Wallpapers
├── docs/
│   ├── bash.md  tmux.md        # existing manuals, relocated
│   └── superpowers/specs/
├── index.html                  # GitHub Pages site
├── .gitignore
└── README.md
```

### Moves and deletions

| From | To | Note |
|---|---|---|
| `nvim/` | `config/nvim/` | contents replaced from machine |
| `tmux/tmux.conf` | `config/tmux/tmux.conf` | replaced from machine |
| `dunst/`, `picom/`, `sxhkd/`, `zathura/` | `config/<name>/` | already identical, move only |
| `bash/bashrc` | `home/bashrc` | replaced from machine |
| `bash/README.md` | `docs/bash.md` | |
| `tmux/README.md` | `docs/tmux.md` | |
| `xdots/xinirc` | `home/xinitrc` | typo fixed, replaced from machine |
| `xdots/xprofile` | `home/xprofile` | replaced from machine |
| `xdots/bash_profile` | `home/bash_profile` | replaced from machine |
| `stColor/Gruvbox` | *deleted* | fragment of st's `config.def.h`, now vendored whole |

## install.sh

Bash, `set -euo pipefail`, sources `lib/*.sh`. Idempotent and re-runnable.
Anything it would clobber is moved to `<path>.bak.<unix-ts>` first.

```
./install.sh                      # all steps
./install.sh --only nvim,suckless # comma-separated step list
./install.sh --skip packages      # inverse
./install.sh --full               # snapshot.txt instead of curated lists
./install.sh --dry-run            # print every action, mutate nothing
./install.sh --yes                # skip the confirmation prompt
```

### Steps

1. **preflight** — assert Arch (`pacman` present), assert not root, prime
   `sudo`, check network reachability. Refuse to continue on failure.
2. **packages** — `pacman -S --needed` from `packages/pacman.txt`.
3. **aur** — bootstrap `yay` if absent, then install `packages/aur.txt`.
4. **link** — apply the link map (below).
5. **suckless** — build and `sudo make install` each of the four tools.
6. **fonts** — `fc-cache -f`; fonts themselves come from the package step.
7. **wallpapers** — copy `Wallpapers/` to `~/Pictures/Wallpapers` (copy, not
   symlink: the directory accumulates machine-local additions).
8. **verify** — assert every symlink resolves, every expected binary is on
   `PATH`, and every font referenced by a suckless config resolves via
   `fc-match`. Print a failure table and `exit 1` if anything is missing.

Step 8 is the correction for the current script's core defect: it must be
impossible for `install.sh` to print success while having done nothing.

### Link map

Declared as data in `lib/link.sh`, consumed by both `link` and `verify`:

| Repo path | Target |
|---|---|
| `config/nvim` | `~/.config/nvim` |
| `config/tmux` | `~/.config/tmux` |
| `config/dunst` | `~/.config/dunst` |
| `config/picom` | `~/.config/picom` |
| `config/sxhkd` | `~/.config/sxhkd` |
| `config/zathura` | `~/.config/zathura` |
| `config/dwmblocks` | `~/.config/dwmblocks` |
| `suckless` | `~/.config/suckless` |
| `home/bashrc` | `~/.bashrc` |
| `home/bash_profile` | `~/.bash_profile` |
| `home/xinitrc` | `~/.xinitrc` |
| `home/xprofile` | `~/.xprofile` |
| `bin/*` | `~/.local/bin/*` |

Symlinking `suckless/` into `~/.config/suckless` is what makes drift
structurally impossible for the configs that drifted worst: editing
`config.def.h` in the place it has always been edited now edits the repo.

## Suckless

### Vendoring

Copy the three trees from `~/.config/suckless/`, delete each `.git`, and
commit. Verified before vendoring: `config.h` is byte-identical to
`config.def.h` in all three, so no customisation is lost by tracking only
`config.def.h` and gitignoring the generated `config.h`.

- **dwm** — upstream git.suckless.org, four patches already applied in the
  working tree. `patches/` retained for provenance:
  `alwayscenter`, `attachbelow`, `bidi-restricted`, `uselessgap`.
  Fonts: `monospace:size=10` with `Noto Sans Arabic` fallback.
- **st** — upstream git.suckless.org, Gruvbox palette.
  Font: `0xProto Nerd Font:size=10`.
- **dmenu** — fork of `github.com/BreadOnPenguins/dmenu`.

### dwmblocks reconstruction

No source survives. Clone `torrinfail/dwmblocks`, vendor it, and write
`blocks.def.h` from the block order recovered out of the installed binary's
string table:

```
ram_usage, ram_temp, cpu_temp, gpu_temp,
vram_usage, vram_temp, volume, battery, date_time
```

All nine scripts exist and are intact in `~/.config/dwmblocks/scripts/`.

**Not recoverable:** per-block delimiters, update intervals, and signal
numbers. Defaults will be chosen (1 s for `date_time`, 10 s for temperature
and usage blocks, 0 with signal for `volume`) and flagged in the README as
the one place the reconstruction is a guess rather than a copy.

## Packages

### Curated

Derived from what the configs actually invoke, not from what is installed:

- **X / WM:** `xorg-server`, `xorg-xinit`, `xorg-xrandr`, `xorg-xsetroot`,
  `xorg-setxkbmap`, `xorg-xkill`, `xorg-xrdb`, `libx11`, `libxinerama`,
  `libxft`, `base-devel`
- **Desktop:** `picom`, `dunst`, `sxhkd`, `feh`, `scrot`, `xdotool`,
  `xclip`, `brightnessctl`, `pamixer`, `libnotify`, `acpi`, `lm_sensors`,
  `xdg-desktop-portal`, `xdg-desktop-portal-gtk`
- **Shell / TUI:** `bash`, `tmux`, `neovim`, `git`, `fzf`, `bat`, `ripgrep`,
  `fd`, `tree`, `nnn`, `zathura`, `zathura-pdf-poppler`, `unzip`, `wget`,
  `curl`, `rsync`
- **Fonts:** `ttf-0xproto-nerd`, `ttf-jetbrains-mono`, `noto-fonts`

`ttf-0xproto-nerd` corrects a real gap: st's font was hand-copied into
`~/.local/share/fonts` and is owned by no package, so a fresh machine would
render st in a fallback face. The package exists in `extra`.

### AUR curated

From `pacman -Qqem`, excluding `-debug` packages (`paru-debug`, `yay-debug`,
`dwl-debug`, `lotion-bin-debug`) and application software unrelated to the
desktop: `ttf-arabeyes-fonts`, `python-pywal`.

### Snapshot

`packages/snapshot.txt` records all 238 explicit native and 19 foreign
packages verbatim, consumed by `--full`. Regenerated by `sync.sh`.

## Hardware conditionals

Three machine-specific assumptions are guarded rather than hardcoded:

1. **Monitor.** `home/xinitrc` currently runs
   `xrandr --output HDMI-1-0 --mode 2560x1440 --rate 144 --right-of eDP`
   unconditionally. Guard on that output being connected:
   ```sh
   xrandr --query | grep -q '^HDMI-1-0 connected' && \
     xrandr --output HDMI-1-0 --mode 2560x1440 --rate 144 --right-of eDP
   ```
   The duplicate copy of this line in `xprofile` is removed; `xinitrc` is
   the single owner.
2. **GPU.** `vram_usage.sh` and `vram_temp.sh` shell out to `nvidia-smi`.
   They already degrade to `N/A`, but a `command -v nvidia-smi` guard makes
   them silent on a machine without it.
3. **Escape hatch.** `home/xinitrc` sources `~/.config/dotfiles/local.sh` if
   present. Gitignored, never committed, for anything else per-machine.

## Custom tooling

`config/sxhkd/sxhkdrc` binds three keys to `study`, a 72 KB bash tool in
`~/.local/share/study` that exists in no repository. It is vendored to
`bin/study/` and symlinked, excluding `logs/log.csv` (personal data).
`battery-monitor.sh` and `deasy` are vendored from `~/.local/bin` likewise.

Without this, three keybindings break on a fresh machine and the tool itself
is one `rm -rf` from being lost.

## Wallpaper reference

`xinitrc` on the machine sets `~/Pictures/Wallpapers/Onyx.png`, which is not
in the repo; the repo's version referenced `cyberpunk.jpg`, which is also not
in the repo. `Onyx.png` (8.5 KB) is added and becomes the referenced default.
The existing 17 wallpapers are kept as-is.

## sync.sh

Reverse direction, for paths that are copied rather than symlinked, plus the
package snapshot:

```
./sync.sh            # report what differs between machine and repo
./sync.sh --apply    # pull machine state into the repo
```

Regenerates `packages/snapshot.txt` and diffs `~/Pictures/Wallpapers`. After
the symlink migration this should report nothing for config files — that it
reports nothing is the evidence the migration worked.

## .gitignore

```
.remember/
suckless/*/config.h
suckless/*/*.o
suckless/dwm/dwm
suckless/st/st
suckless/dmenu/dmenu
suckless/dmenu/stest
suckless/dwmblocks/dwmblocks
suckless/dwmblocks/blocks.h
*.bak.*
```

Listed one path per line: `.gitignore` has no brace expansion.

`config.h` and `blocks.h` are generated from their `.def.h` counterparts by
the Makefiles, so tracking them would guarantee future merge conflicts.

## nvim

Machine wins. `~/.config/nvim` (2026-07-15) is newer than the repo's copy
(2026-05-04). The machine's `snacks.lua` is added; seven plugin files present
only in the repo are deleted at the user's explicit direction:

```
diag.lua  explorer.lua  flash.lua  notify.lua
presence.lua  terminal.lua  todo.lua
```

`lazy-lock.json` is taken from the machine so plugin versions are pinned to
the set known to work.

## Testing

1. `shellcheck` clean on `install.sh`, `sync.sh`, `lib/*.sh`.
2. `./install.sh --dry-run` reviewed against the link map by hand.
3. End-to-end run in an `archlinux` Docker container: packages, links,
   suckless compilation, and the `verify` step. The X session and GPU blocks
   cannot run headless and are excluded; everything else is genuinely
   exercised on a clean system.
4. On the live machine, `./install.sh` must be a no-op apart from replacing
   real files with symlinks to identical content, and `verify` must pass.

A container run is the only way to substantiate "works on a fresh machine".
Claiming it without one repeats the existing script's failure mode.

## Risks

| Risk | Mitigation |
|---|---|
| dwmblocks intervals are guessed | Flagged in README; single known-inexact spot |
| Symlinking `~/.config/suckless` puts root-built `.o` files under the repo | `.gitignore` covers them; `make clean` before first build |
| Replacing live configs with symlinks | Every target backed up to `.bak.<ts>` before touching |
| Curated list misses a package | `verify` catches missing binaries; `--full` is the fallback |
