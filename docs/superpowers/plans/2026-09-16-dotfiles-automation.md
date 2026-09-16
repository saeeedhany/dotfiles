# Dotfiles Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `git clone && ./install.sh` reproduce this Arch + dwm/st/dmenu desktop on a fresh machine, with drift made structurally impossible.

**Architecture:** A restructured repo where every path's install destination is implied by its directory (`config/` → `~/.config`, `home/` → `~`, `bin/` → `~/.local/bin`). A declarative link map in `lib/link.sh` drives both installation and verification. Suckless sources are vendored whole and symlinked back to `~/.config/suckless`, so the place they have always been edited is now the repo.

**Tech Stack:** Bash 5, `bats` (shell unit tests), `shellcheck` (lint), Docker (clean-machine integration test), pacman/yay, GNU make + C toolchain for suckless.

**Spec:** `docs/superpowers/specs/2026-09-16-dotfiles-automation-design.md`

## Global Constraints

- **Arch Linux only.** No Debian/Fedora branches. `detect_distro` is deleted, not ported.
- **Every script starts** `#!/usr/bin/env bash` and `set -euo pipefail`.
- **Every script must pass** `shellcheck -S warning`.
- **`REPO_ROOT`** is resolved in each entrypoint as
  `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` and exported. Library files never resolve it themselves.
- **`DRY_RUN`** is a global (`0`/`1`). Every function that mutates the filesystem or installs packages must honour it.
- **Backups** use the exact suffix `.bak.<unix-timestamp>` via `$(date +%s)`.
- **Idempotency:** every step must be safe to run twice. A second run makes no changes and still exits 0.
- **No silent skips.** A step that cannot do its job calls `die`, or records a failure that the `verify` step reports. The existing script's habit of `warn "... skipping"` followed by "done" is the specific defect being removed.
- **Never `sudo` the whole script.** Individual commands take `sudo`; `preflight` refuses to run as root.
- Commit after every task.

---

### Task 1: Scaffolding, logging library, test harness

**Files:**
- Create: `lib/log.sh`
- Create: `.gitignore`
- Create: `tests/test_helper.bash`
- Test: `tests/log.bats`

**Interfaces:**
- Consumes: nothing
- Produces: `log()`, `info()`, `warn()`, `die()`, `ok()`, `is_dry_run()`, `run_cmd()`. All later tasks use these. `run_cmd "<description>" cmd args...` executes `cmd args...` unless `DRY_RUN=1`, in which case it prints `[dry-run] <description>` and returns 0.

- [ ] **Step 1: Install test tooling**

```bash
sudo pacman -S --needed --noconfirm bats shellcheck
```

- [ ] **Step 2: Write the test helper**

Create `tests/test_helper.bash`:

```bash
#!/usr/bin/env bash
# Shared setup for all bats suites.

setup_repo_root() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT
}

# Give a test an isolated HOME so linking tests cannot touch the real one.
setup_fake_home() {
  FAKE_HOME="$(mktemp -d)"
  export FAKE_HOME
  export HOME="$FAKE_HOME"
}

teardown_fake_home() {
  [[ -n "${FAKE_HOME:-}" && -d "$FAKE_HOME" ]] && rm -rf "$FAKE_HOME"
  return 0
}
```

- [ ] **Step 3: Write the failing test**

Create `tests/log.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  setup_repo_root
  DRY_RUN=0
  source "$REPO_ROOT/lib/log.sh"
}

@test "ok prints a checkmark and the message" {
  run ok "everything fine"
  [ "$status" -eq 0 ]
  [[ "$output" == *"everything fine"* ]]
}

@test "die prints the message and exits 1" {
  run die "fatal thing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fatal thing"* ]]
}

@test "run_cmd executes the command when DRY_RUN=0" {
  local marker="$BATS_TEST_TMPDIR/marker"
  DRY_RUN=0
  run_cmd "create marker" touch "$marker"
  [ -f "$marker" ]
}

@test "run_cmd does not execute the command when DRY_RUN=1" {
  local marker="$BATS_TEST_TMPDIR/marker"
  DRY_RUN=1
  run_cmd "create marker" touch "$marker"
  [ ! -f "$marker" ]
}

@test "run_cmd announces the description when DRY_RUN=1" {
  DRY_RUN=1
  run run_cmd "create marker" touch /tmp/whatever
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"create marker"* ]]
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `bats tests/log.bats`
Expected: FAIL — `lib/log.sh` does not exist.

- [ ] **Step 5: Write lib/log.sh**

```bash
#!/usr/bin/env bash
# Colours and logging primitives shared by every script in this repo.
# Sourced, never executed. Callers set DRY_RUN before using run_cmd.

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'
B='\033[0;34m'; C='\033[0;36m'; D='\033[0;90m'
BOLD='\033[1m'; NC='\033[0m'

log()  { printf "${D}[${NC}${G}+${NC}${D}]${NC} %s\n" "$*"; }
info() { printf "${D}[${NC}${B}*${NC}${D}]${NC} %s\n" "$*"; }
warn() { printf "${D}[${NC}${Y}!${NC}${D}]${NC} %s\n" "$*" >&2; }
ok()   { printf "${D}[${NC}${C}✓${NC}${D}]${NC} %s\n" "$*"; }
die()  { printf "${D}[${NC}${R}✗${NC}${D}]${NC} %s\n" "$*" >&2; exit 1; }

is_dry_run() { [[ "${DRY_RUN:-0}" == "1" ]]; }

# run_cmd <description> <command> [args...]
# Executes the command, or announces it and returns 0 under DRY_RUN.
run_cmd() {
  local desc="$1"; shift
  if is_dry_run; then
    printf "${D}[${NC}${Y}dry-run${NC}${D}]${NC} %s\n" "$desc"
    return 0
  fi
  "$@"
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bats tests/log.bats`
Expected: 5 tests, all PASS.

- [ ] **Step 7: Write .gitignore**

```
.remember/

# Suckless build artifacts. config.h and blocks.h are generated from their
# .def.h counterparts by the Makefiles; tracking them guarantees conflicts.
suckless/*/config.h
suckless/*/*.o
suckless/dwm/dwm
suckless/st/st
suckless/dmenu/dmenu
suckless/dmenu/stest
suckless/dwmblocks/dwmblocks
suckless/dwmblocks/blocks.h

# Installer backups
*.bak.*

# Machine-local, never committed
config/dotfiles/local.sh
```

- [ ] **Step 8: Verify shellcheck is clean**

Run: `shellcheck -S warning lib/log.sh tests/test_helper.bash`
Expected: no output, exit 0.

- [ ] **Step 9: Commit**

```bash
git add lib/log.sh .gitignore tests/
git commit -m "feat: add logging library, gitignore and bats harness"
```

---

### Task 2: Link library

**Files:**
- Create: `lib/link.sh`
- Test: `tests/link.bats`

**Interfaces:**
- Consumes: `lib/log.sh` (`ok`, `warn`, `die`, `run_cmd`, `is_dry_run`), `$REPO_ROOT`
- Produces:
  - `link_map_entries()` — prints one `<repo-relative-src>|<dest>` pair per line, with `$HOME` already expanded.
  - `backup_path <path>` — moves an existing path to `<path>.bak.<ts>`; no-op if nothing is there.
  - `link_one <repo-relative-src> <dest>` — idempotent symlink; returns 1 if the source is missing.
  - `link_all()` — applies every entry from `link_map_entries`.
  - `verify_links()` — returns 0 if every mapped destination is a symlink resolving to its source; prints each failure and returns 1 otherwise.

- [ ] **Step 1: Write the failing test**

Create `tests/link.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  setup_repo_root
  setup_fake_home
  DRY_RUN=0
  source "$REPO_ROOT/lib/log.sh"
  source "$REPO_ROOT/lib/link.sh"
  FAKE_REPO="$(mktemp -d)"
  mkdir -p "$FAKE_REPO/config/demo"
  echo "content" > "$FAKE_REPO/config/demo/file.conf"
  echo "bashrc" > "$FAKE_REPO/home/bashrc" 2>/dev/null || {
    mkdir -p "$FAKE_REPO/home"; echo "bashrc" > "$FAKE_REPO/home/bashrc"; }
  REPO_ROOT="$FAKE_REPO"
}

teardown() {
  teardown_fake_home
  [[ -n "${FAKE_REPO:-}" ]] && rm -rf "$FAKE_REPO"
  return 0
}

@test "link_one creates a symlink pointing at the repo source" {
  link_one "config/demo" "$HOME/.config/demo"
  [ -L "$HOME/.config/demo" ]
  [ "$(readlink -f "$HOME/.config/demo")" = "$(readlink -f "$FAKE_REPO/config/demo")" ]
}

@test "link_one creates missing parent directories" {
  link_one "home/bashrc" "$HOME/deep/nested/.bashrc"
  [ -L "$HOME/deep/nested/.bashrc" ]
}

@test "link_one is idempotent" {
  link_one "config/demo" "$HOME/.config/demo"
  run link_one "config/demo" "$HOME/.config/demo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already linked"* ]]
  run bash -c "ls -d $HOME/.config/*.bak.* 2>/dev/null | wc -l"
  [ "$output" -eq 0 ]
}

@test "link_one backs up an existing real file before replacing it" {
  mkdir -p "$HOME"
  echo "original" > "$HOME/.bashrc"
  link_one "home/bashrc" "$HOME/.bashrc"
  [ -L "$HOME/.bashrc" ]
  run bash -c "cat $HOME/.bashrc.bak.*"
  [ "$output" = "original" ]
}

@test "link_one does not nest when the destination is an existing directory" {
  mkdir -p "$HOME/.config/demo"
  link_one "config/demo" "$HOME/.config/demo"
  [ -L "$HOME/.config/demo" ]
  [ ! -e "$HOME/.config/demo/demo" ]
}

@test "link_one fails when the repo source is missing" {
  run link_one "config/nonexistent" "$HOME/.config/nonexistent"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.config/nonexistent" ]
}

@test "link_one makes no changes under DRY_RUN" {
  DRY_RUN=1
  link_one "config/demo" "$HOME/.config/demo"
  [ ! -e "$HOME/.config/demo" ]
}

@test "verify_links fails when a destination is missing" {
  run verify_links
  [ "$status" -eq 1 ]
}

@test "link_map_entries emits pipe-separated pairs with HOME expanded" {
  run link_map_entries
  [ "$status" -eq 0 ]
  [[ "$output" == *"config/nvim|$HOME/.config/nvim"* ]]
  [[ "$output" == *"suckless|$HOME/.config/suckless"* ]]
  [[ "$output" != *'$HOME'* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/link.bats`
Expected: FAIL — `lib/link.sh` does not exist.

- [ ] **Step 3: Write lib/link.sh**

```bash
#!/usr/bin/env bash
# Declarative map from repo paths to their destinations in $HOME, plus the
# link/backup/verify operations that consume it. Sourced, never executed.
#
# Sourcing this file requires lib/log.sh to be sourced first and REPO_ROOT
# to be set.

# Each entry is "<repo-relative-source>|<destination>".
# bin/ is handled separately: its contents are linked individually so that
# ~/.local/bin can hold entries this repo does not own.
_LINK_MAP=(
  "config/nvim|\$HOME/.config/nvim"
  "config/tmux|\$HOME/.config/tmux"
  "config/dunst|\$HOME/.config/dunst"
  "config/picom|\$HOME/.config/picom"
  "config/sxhkd|\$HOME/.config/sxhkd"
  "config/zathura|\$HOME/.config/zathura"
  "config/dwmblocks|\$HOME/.config/dwmblocks"
  "suckless|\$HOME/.config/suckless"
  "home/bashrc|\$HOME/.bashrc"
  "home/bash_profile|\$HOME/.bash_profile"
  "home/xinitrc|\$HOME/.xinitrc"
  "home/xprofile|\$HOME/.xprofile"
)

link_map_entries() {
  local entry src dest
  for entry in "${_LINK_MAP[@]}"; do
    src="${entry%%|*}"
    dest="${entry#*|}"
    dest="${dest/\$HOME/$HOME}"
    printf '%s|%s\n' "$src" "$dest"
  done
}

# backup_path <path> — move an existing path aside. No-op if absent.
backup_path() {
  local path="$1" stamp
  [[ -e "$path" || -L "$path" ]] || return 0
  stamp="$(date +%s)"
  run_cmd "back up $path -> $path.bak.$stamp" mv "$path" "$path.bak.$stamp"
  warn "backed up $path -> $path.bak.$stamp"
}

# link_one <repo-relative-src> <dest>
link_one() {
  local src="$REPO_ROOT/$1" dest="$2"

  if [[ ! -e "$src" ]]; then
    warn "missing repo source: $1"
    return 1
  fi

  if [[ -L "$dest" ]] && [[ "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
    ok "already linked: $dest"
    return 0
  fi

  backup_path "$dest"
  run_cmd "mkdir -p $(dirname "$dest")" mkdir -p "$(dirname "$dest")"
  # -n keeps ln from descending into an existing directory symlink.
  run_cmd "link $dest -> $src" ln -sfn "$src" "$dest"
  is_dry_run || ok "linked $dest -> $src"
}

link_all() {
  local src dest failed=0
  while IFS='|' read -r src dest; do
    link_one "$src" "$dest" || failed=1
  done < <(link_map_entries)

  # bin/ entries are linked one by one.
  if [[ -d "$REPO_ROOT/bin" ]]; then
    local f
    for f in "$REPO_ROOT/bin"/*; do
      [[ -e "$f" ]] || continue
      link_one "bin/$(basename "$f")" "$HOME/.local/bin/$(basename "$f")" || failed=1
    done
  fi

  return "$failed"
}

# verify_links — prints every mapping that is not a correct symlink.
verify_links() {
  local src dest failed=0
  while IFS='|' read -r src dest; do
    if [[ ! -L "$dest" ]]; then
      warn "not a symlink: $dest"
      failed=1
    elif [[ "$(readlink -f "$dest")" != "$(readlink -f "$REPO_ROOT/$src")" ]]; then
      warn "wrong target: $dest -> $(readlink -f "$dest")"
      failed=1
    fi
  done < <(link_map_entries)
  return "$failed"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/link.bats`
Expected: 9 tests, all PASS.

Note: the `link_map_entries` test passes because the map is static data; the fake repo in `setup` does not need those directories to exist for that test.

- [ ] **Step 5: Lint**

Run: `shellcheck -S warning lib/link.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/link.sh tests/link.bats
git commit -m "feat: add declarative link map with backup and verification"
```

---

### Task 3: Package library

**Files:**
- Create: `lib/pkg.sh`
- Test: `tests/pkg.bats`

**Interfaces:**
- Consumes: `lib/log.sh`
- Produces:
  - `read_pkg_list <file>` — prints one package name per line, stripping `#` comments, inline comments, and blank lines.
  - `pkg_install <file>` — `sudo pacman -S --needed --noconfirm` for the list.
  - `ensure_yay()` — installs `yay` from AUR if absent.
  - `aur_install <file>` — `yay -S --needed --noconfirm` for the list.

- [ ] **Step 1: Write the failing test**

Create `tests/pkg.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  setup_repo_root
  DRY_RUN=0
  source "$REPO_ROOT/lib/log.sh"
  source "$REPO_ROOT/lib/pkg.sh"
  LIST="$BATS_TEST_TMPDIR/list.txt"
}

@test "read_pkg_list strips comments and blank lines" {
  cat > "$LIST" <<'EOF'
# X server
xorg-server

xorg-xinit
# trailing comment block
picom
EOF
  run read_pkg_list "$LIST"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "xorg-server" ]
  [ "${lines[1]}" = "xorg-xinit" ]
  [ "${lines[2]}" = "picom" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "read_pkg_list strips inline comments and surrounding whitespace" {
  printf '  feh   # wallpaper setter\n' > "$LIST"
  run read_pkg_list "$LIST"
  [ "$output" = "feh" ]
}

@test "read_pkg_list fails on a missing file" {
  run read_pkg_list "$BATS_TEST_TMPDIR/nope.txt"
  [ "$status" -ne 0 ]
}

@test "read_pkg_list returns nothing for a comment-only file" {
  printf '# just a comment\n\n' > "$LIST"
  run read_pkg_list "$LIST"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pkg_install does not invoke pacman under DRY_RUN" {
  printf 'somepackage\n' > "$LIST"
  DRY_RUN=1
  run pkg_install "$LIST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/pkg.bats`
Expected: FAIL — `lib/pkg.sh` does not exist.

- [ ] **Step 3: Write lib/pkg.sh**

```bash
#!/usr/bin/env bash
# Package installation helpers. Arch only, by design.
# Sourced, never executed. Requires lib/log.sh.

# read_pkg_list <file> — one package per line, comments and blanks removed.
read_pkg_list() {
  local file="$1"
  [[ -f "$file" ]] || { warn "package list not found: $file"; return 1; }
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$file" \
    | grep -v '^$' || true
}

pkg_install() {
  local file="$1"
  local -a pkgs
  mapfile -t pkgs < <(read_pkg_list "$file")
  if [[ "${#pkgs[@]}" -eq 0 ]]; then
    warn "no packages listed in $file"
    return 0
  fi
  log "installing ${#pkgs[@]} packages from $(basename "$file")..."
  run_cmd "pacman -S --needed ${#pkgs[@]} packages" \
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"
  ok "native packages installed"
}

ensure_yay() {
  if command -v yay &>/dev/null; then
    ok "yay already present"
    return 0
  fi
  log "bootstrapping yay from AUR..."
  run_cmd "install yay build deps" \
    sudo pacman -S --needed --noconfirm git base-devel
  local build_dir
  build_dir="$(mktemp -d)"
  run_cmd "clone yay" git clone --depth=1 https://aur.archlinux.org/yay.git "$build_dir/yay"
  if ! is_dry_run; then
    ( cd "$build_dir/yay" && makepkg -si --noconfirm )
  fi
  rm -rf "$build_dir"
  ok "yay installed"
}

aur_install() {
  local file="$1"
  local -a pkgs
  mapfile -t pkgs < <(read_pkg_list "$file")
  if [[ "${#pkgs[@]}" -eq 0 ]]; then
    warn "no AUR packages listed in $file"
    return 0
  fi
  ensure_yay
  log "installing ${#pkgs[@]} AUR packages..."
  run_cmd "yay -S --needed ${#pkgs[@]} packages" \
    yay -S --needed --noconfirm "${pkgs[@]}"
  ok "AUR packages installed"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/pkg.bats`
Expected: 5 tests, all PASS.

- [ ] **Step 5: Lint and commit**

```bash
shellcheck -S warning lib/pkg.sh
git add lib/pkg.sh tests/pkg.bats
git commit -m "feat: add package installation helpers"
```

---

### Task 4: Restructure the repo and pull machine state in

This task performs the moves from the spec's "Moves and deletions" table and replaces drifted content with the machine's version. Machine wins, per the approved spec.

**Files:**
- Move: `nvim/` → `config/nvim/`, `tmux/tmux.conf` → `config/tmux/tmux.conf`, `dunst/`, `picom/`, `sxhkd/`, `zathura/` → `config/<name>/`
- Move: `bash/bashrc` → `home/bashrc`, `xdots/{xinirc,xprofile,bash_profile}` → `home/{xinitrc,xprofile,bash_profile}`
- Move: `bash/README.md` → `docs/bash.md`, `tmux/README.md` → `docs/tmux.md`
- Delete: `stColor/Gruvbox`, and seven nvim plugin files
- Create: `config/dwmblocks/scripts/` (from machine)

- [ ] **Step 1: Move files with git mv, preserving history**

```bash
mkdir -p config home docs
git mv nvim config/nvim
mkdir -p config/tmux && git mv tmux/tmux.conf config/tmux/tmux.conf
git mv dunst config/dunst
git mv picom config/picom
git mv sxhkd config/sxhkd
git mv zathura config/zathura
git mv bash/bashrc home/bashrc
git mv bash/README.md docs/bash.md
git mv tmux/README.md docs/tmux.md
git mv xdots/xinirc home/xinitrc
git mv xdots/xprofile home/xprofile
git mv xdots/bash_profile home/bash_profile
git rm -r stColor
rmdir bash tmux xdots 2>/dev/null || true
```

- [ ] **Step 2: Replace drifted configs with the machine's version**

```bash
cp ~/.bashrc              home/bashrc
cp ~/.bash_profile        home/bash_profile
cp ~/.xinitrc             home/xinitrc
cp ~/.xprofile            home/xprofile
cp ~/.config/tmux/tmux.conf config/tmux/tmux.conf
rsync -a --delete ~/.config/nvim/ config/nvim/
mkdir -p config/dwmblocks
rsync -a ~/.config/dwmblocks/scripts/ config/dwmblocks/scripts/
```

`rsync --delete` on nvim is what removes the seven repo-only plugin files (`diag.lua`, `explorer.lua`, `flash.lua`, `notify.lua`, `presence.lua`, `terminal.lua`, `todo.lua`) and adds the machine's `snacks.lua`. This is the user's explicit instruction.

- [ ] **Step 3: Verify the nvim delta is exactly what the spec predicted**

```bash
git status --porcelain config/nvim | sort
```

Expected: deletions for the seven plugin files listed above, an addition for `lua/plugins/snacks.lua`, and modifications to `init.lua`, `lazy-lock.json`, `lua/core/keymaps.lua`, `lua/core/options.lua`, `lua/plugins/fuzzy.lua`, `lua/plugins/theme.lua`, `lua/plugins/tsitter.lua`, `lua/plugins/ui.lua`. If anything else appears, stop and report it.

- [ ] **Step 4: Confirm the previously-identical configs are still identical**

```bash
diff -r config/dunst   ~/.config/dunst   && echo "dunst OK"
diff -r config/picom   ~/.config/picom   && echo "picom OK"
diff -r config/sxhkd   ~/.config/sxhkd   && echo "sxhkd OK"
diff -r config/zathura ~/.config/zathura && echo "zathura OK"
```

Expected: four `OK` lines, no diff output.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: restructure into config/ home/ docs/, sync from machine

Machine state wins per spec. Drops seven nvim plugin files with no
counterpart on the machine and adds snacks.lua. Deletes stColor/Gruvbox,
a fragment of st's config.def.h now vendored whole."
```

---

### Task 5: Vendor dwm, st and dmenu

**Files:**
- Create: `suckless/dwm/`, `suckless/st/`, `suckless/dmenu/`

- [ ] **Step 1: Confirm no customisation is lost by tracking only config.def.h**

```bash
for t in dwm st dmenu; do
  if diff -q ~/.config/suckless/$t/config.def.h ~/.config/suckless/$t/config.h >/dev/null; then
    echo "$t: config.h == config.def.h, safe"
  else
    echo "$t: DIVERGED — stop and reconcile before vendoring"
  fi
done
```

Expected: three `safe` lines. If any reports `DIVERGED`, halt — the generated `config.h` holds edits that `config.def.h` does not, and vendoring would lose them.

- [ ] **Step 2: Copy the trees in, without their git history or build artifacts**

```bash
mkdir -p suckless
for t in dwm st dmenu; do
  rsync -a --exclude='.git' ~/.config/suckless/$t/ suckless/$t/
  ( cd "suckless/$t" && make clean >/dev/null 2>&1 || true )
  rm -f suckless/$t/config.h
done
```

`make clean` plus removing `config.h` leaves only tracked sources; `.gitignore` from Task 1 covers anything regenerated.

- [ ] **Step 3: Remove root-owned artifacts that make clean may have missed**

```bash
find suckless -name '*.o' -delete
rm -f suckless/dwm/dwm suckless/st/st suckless/dmenu/dmenu suckless/dmenu/stest
ls -la suckless/dwm suckless/st suckless/dmenu | grep -c root || echo "no root-owned files remain"
```

Expected: `no root-owned files remain`. Some artifacts are root-owned because the original builds ran under `sudo`; use `sudo rm` if a plain `rm` is refused.

- [ ] **Step 4: Verify each tree builds from a clean state**

```bash
for t in dwm st dmenu; do
  ( cd "suckless/$t" && make clean >/dev/null && make >/dev/null 2>&1 \
      && echo "$t builds" || echo "$t FAILED" )
done
```

Expected: `dwm builds`, `st builds`, `dmenu builds`.

- [ ] **Step 5: Clean the build output back out before committing**

```bash
for t in dwm st dmenu; do ( cd "suckless/$t" && make clean >/dev/null ); done
rm -f suckless/*/config.h
git status --porcelain suckless | grep -E '\.o$|config\.h$' && echo "ARTIFACTS LEAKED" || echo "clean"
```

Expected: `clean`.

- [ ] **Step 6: Confirm the expected customisations survived**

```bash
grep -q 'gappx' suckless/dwm/config.def.h && echo "dwm uselessgap patch present"
grep -q 'Noto Sans Arabic' suckless/dwm/config.def.h && echo "dwm arabic fallback present"
grep -q '0xProto Nerd Font' suckless/st/config.def.h && echo "st font present"
grep -q '0xProto Nerd Font' suckless/dmenu/config.def.h && echo "dmenu font present"
grep -q '#282828' suckless/st/config.def.h && echo "st gruvbox present"
ls suckless/dwm/patches/ | wc -l
```

Expected: five confirmation lines and `4` patches.

- [ ] **Step 7: Commit**

```bash
git add suckless/
git commit -m "feat: vendor dwm, st and dmenu sources

Previously absent from the repo entirely: a fresh clone produced no
window manager, terminal or launcher. Trees copied from
~/.config/suckless with .git removed. dwm carries four applied patches
(alwayscenter, attachbelow, bidi-restricted, uselessgap)."
```

---

### Task 6: Reconstruct dwmblocks

The installed binary is the only surviving record of this configuration. The whole `blocks[]` array is recoverable from its `.data.rel.ro` section; this task rebuilds it and proves the reconstruction is exact.

**Files:**
- Create: `suckless/dwmblocks/` (upstream `torrinfail/dwmblocks` plus a rebuilt `blocks.def.h`)

**Interfaces:**
- Consumes: `config/dwmblocks/scripts/` from Task 4 — the nine scripts the blocks invoke.
- Produces: a `dwmblocks` binary whose `.rodata` matches the original's.

- [ ] **Step 1: Vendor upstream**

```bash
mkdir -p suckless
git clone --depth=1 https://github.com/torrinfail/dwmblocks.git suckless/dwmblocks
rm -rf suckless/dwmblocks/.git
```

- [ ] **Step 2: Record the original binary's strings for later comparison**

```bash
objdump -s -j .rodata /usr/local/bin/dwmblocks > /tmp/dwmblocks-original-rodata.txt
wc -l /tmp/dwmblocks-original-rodata.txt
```

Keep this file; Step 5 diffs against it.

- [ ] **Step 3: Write the reconstructed blocks.def.h**

The icons are Nerd Font glyphs above U+FFFF. Generate the file with explicit
byte escapes rather than pasting glyphs, so no editor or clipboard can mangle
them:

```bash
printf '%s\n' \
'//Modify this file to change what commands output to your statusbar, and recompile using the make command.' \
'static const Block blocks[] = {' \
'	/*Icon*/	/*Command*/	/*Update Interval*/	/*Update Signal*/' \
> suckless/dwmblocks/blocks.def.h

emit_block() {
  # emit_block <icon-escape> <script> <interval>
  printf '\t{"%b ", "~/.config/dwmblocks/scripts/%s",\t%s,\t0},\n' \
    "$1" "$2" "$3" >> suckless/dwmblocks/blocks.def.h
}

emit_block '\xf3\xb0\x8d\x9b' 'ram_usage.sh'   2
emit_block '\xf3\xb0\x94\x84' 'ram_temp.sh'    5
emit_block '\xf3\xb0\x8b\x9b' 'cpu_temp.sh'    2
emit_block '\xf3\xb0\xa2\xae' 'gpu_temp.sh'    2
emit_block '\xf3\xb0\xbe\xb2' 'vram_usage.sh'  2
emit_block '\xf3\xb0\xbe\xb4' 'vram_temp.sh'   5
emit_block '\xef\x80\xa8'     'volume'         1
emit_block '\xef\x89\x80'     'battery'        30
emit_block '\xef\x81\xb3'     'date_time'      1

printf '%s\n' \
'};' \
'' \
"//sets delimiter between status commands. NULL character ('\\0') means no delimiter." \
'static char delim[] = " | ";' \
'static unsigned int delimLen = 5;' \
>> suckless/dwmblocks/blocks.def.h
```

Icon codepoints, decoded from the original binary's `.rodata`:

| Escape | Codepoint | Block |
|---|---|---|
| `\xf3\xb0\x8d\x9b` | U+F035B | ram_usage |
| `\xf3\xb0\x94\x84` | U+F0504 | ram_temp |
| `\xf3\xb0\x8b\x9b` | U+F02DB | cpu_temp |
| `\xf3\xb0\xa2\xae` | U+F08AE | gpu_temp |
| `\xf3\xb0\xbe\xb2` | U+F0FB2 | vram_usage |
| `\xf3\xb0\xbe\xb4` | U+F0FB4 | vram_temp |
| `\xef\x80\xa8` | U+F028 | volume |
| `\xef\x89\x80` | U+F240 | battery |
| `\xef\x81\xb3` | U+F073 | date_time |

- [ ] **Step 4: Build it**

```bash
( cd suckless/dwmblocks && make clean >/dev/null 2>&1; make )
```

Expected: compiles, producing `suckless/dwmblocks/dwmblocks`.

- [ ] **Step 5: Prove the reconstruction is exact**

This is the test. Both binaries' `.rodata` hold the same icon and command
strings in the same order, so their hexdumps must match:

```bash
objdump -s -j .rodata suckless/dwmblocks/dwmblocks > /tmp/dwmblocks-rebuilt-rodata.txt
diff <(grep -oE '[0-9a-f]{8} .*' /tmp/dwmblocks-original-rodata.txt | cut -c10-) \
     <(grep -oE '[0-9a-f]{8} .*' /tmp/dwmblocks-rebuilt-rodata.txt  | cut -c10-) \
  && echo "RODATA IDENTICAL — reconstruction exact" \
  || echo "RODATA DIFFERS — inspect before continuing"
```

Expected: `RODATA IDENTICAL — reconstruction exact`.

If it differs, diff the two dumps directly and compare against the codepoint table in Step 3 — a mismatch means an icon escape was transcribed wrong.

- [ ] **Step 6: Verify the block structure independently**

```bash
objdump -s -j .data.rel.ro suckless/dwmblocks/dwmblocks | head -20
```

Expected: nine 24-byte records whose third field reads `02, 05, 02, 02, 02, 05, 01, 1e, 01` — the intervals 2, 5, 2, 2, 2, 5, 1, 30, 1.

- [ ] **Step 7: Clean and commit**

```bash
( cd suckless/dwmblocks && make clean >/dev/null )
rm -f suckless/dwmblocks/blocks.h
git add suckless/dwmblocks
git commit -m "feat: reconstruct dwmblocks from the installed binary

The source existed nowhere: only /usr/local/bin/dwmblocks and the nine
scripts survived. The complete blocks[] array was recovered from the
binary's .data.rel.ro section and verified by rebuilding and diffing
.rodata against the original. Only delimLen is not attributable; upstream's
value of 5 is used and renders identically."
```

---

### Task 7: Vendor local scripts

`config/sxhkd/sxhkdrc` binds Super+Shift+Y, Super+Ctrl+Y and Super+Alt+Y to `study`, which exists only at `~/.local/share/study` and is in no repository.

**Files:**
- Create: `bin/battery-monitor.sh`, `bin/deasy`, `bin/study/`

- [ ] **Step 1: Copy the standalone scripts**

```bash
mkdir -p bin
cp ~/.local/bin/battery-monitor.sh bin/
cp ~/.local/bin/deasy bin/
chmod +x bin/battery-monitor.sh bin/deasy
```

- [ ] **Step 2: Vendor the study tool, excluding its personal log**

```bash
rsync -a --exclude='logs/' ~/.local/share/study/ bin/study/
mkdir -p bin/study/logs
touch bin/study/logs/.gitkeep
chmod +x bin/study/bin/study
```

`logs/log.csv` is the user's actual study history, not configuration, and is excluded deliberately.

- [ ] **Step 3: Confirm no secrets came along**

```bash
grep -rIE '(api[_-]?key|token|password|secret)[[:space:]]*=' bin/ \
  && echo "REVIEW THESE BEFORE COMMITTING" || echo "no obvious secrets"
cat bin/study/config/settings.conf
```

Expected: `no obvious secrets`. Read `settings.conf` regardless — it is short, and this is the moment to catch anything machine-specific or private before it is committed to a public repo.

- [ ] **Step 4: Verify the sxhkd bindings now have a source in-repo**

```bash
grep -n 'study' config/sxhkd/sxhkdrc
test -x bin/study/bin/study && echo "study vendored and executable"
```

Expected: three binding lines and the confirmation.

- [ ] **Step 5: Commit**

```bash
git add bin/
git commit -m "feat: vendor local scripts including the study tool

Three sxhkd bindings invoked 'study', which lived only in
~/.local/share/study and was tracked nowhere. Personal log excluded."
```

---

### Task 8: Package lists

**Files:**
- Create: `packages/pacman.txt`, `packages/aur.txt`, `packages/snapshot.txt`

- [ ] **Step 1: Write the curated native list**

Create `packages/pacman.txt`:

```
# Curated dependencies for this desktop. Derived from what the configs
# actually invoke, not from everything installed on the origin machine.
# For an exact clone of that machine, use: ./install.sh --full

# ── build toolchain (suckless is compiled from source) ──
base-devel
git
libx11
libxinerama
libxft

# ── X server and session ──
xorg-server
xorg-xinit
xorg-xrandr
xorg-xsetroot
xorg-setxkbmap
xorg-xkill
xorg-xrdb
xdg-desktop-portal
xdg-desktop-portal-gtk

# ── desktop ──
picom
dunst
sxhkd
feh
scrot
xdotool
xclip
brightnessctl
pamixer
libnotify
acpi
lm_sensors

# ── shell and TUI ──
tmux
neovim
fzf
bat
ripgrep
fd
tree
nnn
zathura
zathura-pdf-poppler

# ── fonts ──
# st and dmenu both request "0xProto Nerd Font". On the origin machine this
# font was hand-copied into ~/.local/share/fonts and owned by no package,
# so a fresh install would silently fall back to another face.
ttf-0xproto-nerd
ttf-jetbrains-mono
noto-fonts

# ── misc ──
curl
wget
unzip
rsync
```

- [ ] **Step 2: Write the curated AUR list**

Create `packages/aur.txt`:

```
# AUR packages needed by this desktop.
# Excluded from the origin machine's foreign-package list: all -debug
# packages (paru-debug, yay-debug, dwl-debug, lotion-bin-debug) and
# application software unrelated to the desktop.

ttf-arabeyes-fonts
python-pywal
```

- [ ] **Step 3: Generate the full snapshot**

```bash
mkdir -p packages
{
  echo "# Full package snapshot of the origin machine."
  echo "# Generated $(date -I) by sync.sh. Consumed by ./install.sh --full"
  echo
  echo "# ── native, explicitly installed ──"
  pacman -Qqen
  echo
  echo "# ── foreign (AUR) ──"
  pacman -Qqem
} > packages/snapshot.txt
wc -l packages/snapshot.txt
```

- [ ] **Step 4: Verify every curated package actually exists in the repos**

This catches typos now rather than half-way through someone's install:

```bash
missing=0
while read -r p; do
  pacman -Si "$p" &>/dev/null || { echo "NOT IN REPOS: $p"; missing=1; }
done < <(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
             packages/pacman.txt | grep -v '^$')
[ "$missing" -eq 0 ] && echo "all curated native packages resolve"
```

Expected: `all curated native packages resolve`.

- [ ] **Step 5: Verify the curated list covers every binary the configs invoke**

```bash
for b in picom dunst sxhkd feh scrot xdotool xclip brightnessctl pamixer \
         notify-send acpi sensors tmux nvim fzf bat rg fd tree nnn zathura \
         setxkbmap xrandr xsetroot xkill; do
  command -v "$b" >/dev/null || echo "NOT ON PATH: $b"
done
echo "coverage check done"
```

Every name should resolve on the origin machine. Any that does not indicates a package missing from `pacman.txt`; add it.

- [ ] **Step 6: Commit**

```bash
git add packages/
git commit -m "feat: add curated and snapshot package lists

Curated list adds ttf-0xproto-nerd, which st and dmenu both require but
which was unmanaged on the origin machine."
```

---

### Task 9: Hardware conditionals

**Files:**
- Modify: `home/xinitrc`, `home/xprofile`, `home/bash_profile`
- Modify: `config/dwmblocks/scripts/vram_usage.sh`, `config/dwmblocks/scripts/vram_temp.sh`
- Create: `Wallpapers/Onyx.png`

- [ ] **Step 1: Add the wallpaper that xinitrc actually references**

`xinitrc` will point at `Onyx.png`, which is on the machine but not in the
repo. The old repo version referenced `cyberpunk.jpg`, which is not in the
repo either — that line has been broken on a fresh clone all along.

```bash
cp ~/Pictures/Wallpapers/Onyx.png Wallpapers/Onyx.png
ls -la Wallpapers/Onyx.png
```

Expected: an 8.5 KB file. The other 17 wallpapers are kept as-is per the
user's instruction.

- [ ] **Step 2: Rewrite home/xinitrc with guards**

The machine's version hardcodes a specific monitor. Replace the file with:

```bash
#!/bin/sh

setxkbmap -option caps:swapescape

# Second monitor, only when it is actually attached.
if xrandr --query | grep -q '^HDMI-1-0 connected'; then
  xrandr --output HDMI-1-0 --mode 2560x1440 --rate 144 --right-of eDP
fi

# Machine-local overrides: extra monitors, per-host env, anything that
# should not be committed. Gitignored; absent by default.
[ -f "$HOME/.config/dotfiles/local.sh" ] && . "$HOME/.config/dotfiles/local.sh"

dwmblocks &
dunst &
sxhkd &
picom &
feh --bg-fill "$HOME/Pictures/Wallpapers/Onyx.png" &

/usr/lib/xdg-desktop-portal-gtk &
/usr/lib/xdg-desktop-portal &

exec dbus-run-session dwm
```

- [ ] **Step 3: Rewrite home/xprofile**

The `xrandr` line was duplicated across `xinitrc` and `xprofile`; `xinitrc` is now its sole owner.

```bash
export QT_STYLE_OVERRIDE=kvantum
```

- [ ] **Step 4: Make home/bash_profile portable**

The machine's copy hardcodes `/home/saeed`. Replace that block so the file works for any user:

```bash
#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

if [ -z "${DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then
	exec startx
fi

## [Completion]
## Completion scripts setup. Remove the following line to uninstall
[ -f "$HOME/.dart-cli-completion/bash-config.bash" ] && . "$HOME/.dart-cli-completion/bash-config.bash" || true
## [/Completion]
```

- [ ] **Step 5: Guard the nvidia blocks**

`config/dwmblocks/scripts/vram_usage.sh`:

```bash
#!/bin/sh

command -v nvidia-smi >/dev/null 2>&1 || { echo "N/A"; exit 0; }

nvidia-smi \
  --query-gpu=memory.used,memory.total \
  --format=csv,noheader,nounits 2>/dev/null \
| awk -F',' '{printf "%d/%dMB\n",$1,$2}'
```

`config/dwmblocks/scripts/vram_temp.sh`:

```bash
#!/bin/sh

command -v nvidia-smi >/dev/null 2>&1 || { echo "N/A"; exit 0; }

temp=$(nvidia-smi \
  --query-gpu=temperature.gpu \
  --format=csv,noheader,nounits 2>/dev/null)

[ -n "$temp" ] && echo "${temp}°C" || echo "N/A"
```

- [ ] **Step 6: Verify the guards behave on a machine without the hardware**

```bash
chmod +x config/dwmblocks/scripts/*.sh
env PATH=/usr/bin:/bin sh -c 'PATH=/nonexistent config/dwmblocks/scripts/vram_usage.sh'
env PATH=/usr/bin:/bin sh -c 'PATH=/nonexistent config/dwmblocks/scripts/vram_temp.sh'
```

Expected: each prints `N/A` and exits 0.

- [ ] **Step 7: Verify xinitrc is still valid shell and the guard works**

```bash
sh -n home/xinitrc && echo "xinitrc syntax OK"
sh -n home/xprofile && echo "xprofile syntax OK"
bash -n home/bash_profile && echo "bash_profile syntax OK"
grep -c 'xrandr' home/xprofile
```

Expected: three `OK` lines and `0` xrandr references left in `xprofile`.

- [ ] **Step 8: Commit**

```bash
git add home/ config/dwmblocks/scripts/ Wallpapers/Onyx.png
git commit -m "feat: guard machine-specific monitor and GPU assumptions

xrandr now runs only when HDMI-1-0 is connected, and was deduplicated
from xprofile. nvidia blocks short-circuit when nvidia-smi is absent.
bash_profile no longer hardcodes /home/saeed. Adds an optional
~/.config/dotfiles/local.sh escape hatch."
```

---

### Task 10: install.sh orchestrator

**Files:**
- Rewrite: `install.sh` (the existing file is deleted wholesale — it targets a layout that never existed here)
- Test: `tests/install_args.bats`

**Interfaces:**
- Consumes: `lib/log.sh`, `lib/link.sh`, `lib/pkg.sh`
- Produces: `parse_args "$@"` setting `DRY_RUN`, `ASSUME_YES`, `USE_FULL`, and the array `STEPS_TO_RUN`; `should_run <step>` returning 0 when a step is selected.

- [ ] **Step 1: Write the failing test**

Create `tests/install_args.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  setup_repo_root
  source "$REPO_ROOT/lib/log.sh"
  # Pull in only the argument-parsing half of install.sh.
  INSTALL_SOURCED_FOR_TEST=1
  source "$REPO_ROOT/install.sh"
}

@test "defaults run every step" {
  parse_args
  should_run preflight
  should_run packages
  should_run link
  should_run suckless
  should_run verify
}

@test "--dry-run sets DRY_RUN" {
  parse_args --dry-run
  [ "$DRY_RUN" -eq 1 ]
}

@test "--only restricts to the named steps" {
  parse_args --only link,suckless
  should_run link
  should_run suckless
  ! should_run packages
  ! should_run fonts
}

@test "--skip removes the named steps" {
  parse_args --skip packages,aur
  should_run link
  ! should_run packages
  ! should_run aur
}

@test "--full sets USE_FULL" {
  parse_args --full
  [ "$USE_FULL" -eq 1 ]
}

@test "--yes sets ASSUME_YES" {
  parse_args --yes
  [ "$ASSUME_YES" -eq 1 ]
}

@test "an unknown flag exits non-zero" {
  run parse_args --nonsense
  [ "$status" -ne 0 ]
}

@test "an unknown step name exits non-zero" {
  run parse_args --only notastep
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/install_args.bats`
Expected: FAIL — `parse_args` is not defined.

- [ ] **Step 3: Write install.sh**

```bash
#!/usr/bin/env bash
# ThePrimeSetup.conf — bootstrap installer for Arch Linux.
# usage: git clone https://github.com/saeeedhany/ThePrimeSetup.conf && ./install.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT

# shellcheck source=lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=lib/pkg.sh
source "$REPO_ROOT/lib/pkg.sh"
# shellcheck source=lib/link.sh
source "$REPO_ROOT/lib/link.sh"

ALL_STEPS=(preflight packages aur link suckless fonts wallpapers verify)

DRY_RUN=0
ASSUME_YES=0
USE_FULL=0
STEPS_TO_RUN=()

usage() {
  cat <<'EOF'
usage: ./install.sh [options]

  --only  a,b,c   run only these steps
  --skip  a,b,c   run everything except these steps
  --full          install packages/snapshot.txt instead of the curated lists
  --dry-run       print every action without performing it
  --yes           do not prompt for confirmation
  -h, --help      show this message

steps: preflight packages aur link suckless fonts wallpapers verify
EOF
}

_is_valid_step() {
  local candidate="$1" s
  for s in "${ALL_STEPS[@]}"; do
    [[ "$s" == "$candidate" ]] && return 0
  done
  return 1
}

parse_args() {
  local only="" skip=""
  DRY_RUN=0; ASSUME_YES=0; USE_FULL=0; STEPS_TO_RUN=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --only)    only="$2"; shift 2 ;;
      --skip)    skip="$2"; shift 2 ;;
      --full)    USE_FULL=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --yes|-y)  ASSUME_YES=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *)         warn "unknown option: $1"; usage; return 2 ;;
    esac
  done

  local s
  if [[ -n "$only" ]]; then
    IFS=',' read -ra STEPS_TO_RUN <<< "$only"
    for s in "${STEPS_TO_RUN[@]}"; do
      _is_valid_step "$s" || { warn "unknown step: $s"; return 2; }
    done
  else
    STEPS_TO_RUN=("${ALL_STEPS[@]}")
  fi

  if [[ -n "$skip" ]]; then
    local -a to_skip keep=()
    IFS=',' read -ra to_skip <<< "$skip"
    for s in "${to_skip[@]}"; do
      _is_valid_step "$s" || { warn "unknown step: $s"; return 2; }
    done
    local candidate skipped
    for candidate in "${STEPS_TO_RUN[@]}"; do
      skipped=0
      for s in "${to_skip[@]}"; do
        [[ "$candidate" == "$s" ]] && skipped=1
      done
      [[ "$skipped" -eq 0 ]] && keep+=("$candidate")
    done
    STEPS_TO_RUN=("${keep[@]}")
  fi

  return 0
}

should_run() {
  local wanted="$1" s
  for s in "${STEPS_TO_RUN[@]}"; do
    [[ "$s" == "$wanted" ]] && return 0
  done
  return 1
}

# ── steps ──────────────────────────────────────────────────────────────────

step_preflight() {
  log "preflight..."
  command -v pacman &>/dev/null || die "this installer is Arch-only (no pacman found)"
  [[ "$EUID" -ne 0 ]] || die "do not run this as root; it uses sudo where needed"
  command -v sudo &>/dev/null || die "sudo is required"
  ping -c1 -W3 archlinux.org &>/dev/null || warn "no network — package steps will fail"
  is_dry_run || sudo -v
  ok "preflight passed"
}

step_packages() {
  if [[ "$USE_FULL" -eq 1 ]]; then
    pkg_install "$REPO_ROOT/packages/snapshot.txt"
  else
    pkg_install "$REPO_ROOT/packages/pacman.txt"
  fi
}

step_aur() {
  [[ "$USE_FULL" -eq 1 ]] && { info "--full: AUR packages came from the snapshot"; return 0; }
  aur_install "$REPO_ROOT/packages/aur.txt"
}

step_link() {
  log "linking configuration..."
  link_all || die "one or more links could not be created"
  ok "configuration linked"
}

step_suckless() {
  log "building suckless tools..."
  local tool
  for tool in dwm st dmenu dwmblocks; do
    local dir="$REPO_ROOT/suckless/$tool"
    [[ -d "$dir" ]] || die "missing vendored source: suckless/$tool"
    log "  building $tool..."
    run_cmd "make clean in $tool" make -C "$dir" clean
    run_cmd "make $tool"          make -C "$dir"
    run_cmd "install $tool"       sudo make -C "$dir" install
    ok "  $tool installed"
  done
}

step_fonts() {
  log "refreshing font cache..."
  run_cmd "fc-cache -f" fc-cache -f
  ok "font cache refreshed"
}

step_wallpapers() {
  log "copying wallpapers..."
  run_cmd "mkdir -p ~/Pictures/Wallpapers" mkdir -p "$HOME/Pictures/Wallpapers"
  # Copied rather than symlinked: the directory accumulates machine-local
  # additions that should not become repo changes.
  run_cmd "rsync wallpapers" rsync -a "$REPO_ROOT/Wallpapers/" "$HOME/Pictures/Wallpapers/"
  ok "wallpapers copied"
}

step_verify() {
  log "verifying installation..."
  local failed=0

  verify_links || failed=1

  local b
  for b in dwm st dmenu dwmblocks sxhkd picom dunst feh nvim tmux; do
    command -v "$b" &>/dev/null || { warn "not on PATH: $b"; failed=1; }
  done

  # st and dmenu both request this face by name; a fallback would be silent.
  if command -v fc-match &>/dev/null; then
    local matched
    matched="$(fc-match '0xProto Nerd Font' 2>/dev/null || true)"
    [[ "$matched" == *"0xProto"* ]] || { warn "0xProto Nerd Font not installed"; failed=1; }
  fi

  if [[ "$failed" -ne 0 ]]; then
    die "verification FAILED — see the warnings above"
  fi
  ok "verification passed"
}

# ── main ───────────────────────────────────────────────────────────────────

main() {
  parse_args "$@" || exit $?

  printf "\n${D}┌─────────────────────────────────────────┐${NC}\n"
  printf "${D}│${NC}  ${BOLD}ThePrimeSetup.conf${NC} — bootstrap          ${D}│${NC}\n"
  printf "${D}└─────────────────────────────────────────┘${NC}\n\n"

  is_dry_run && warn "DRY RUN — nothing will be modified"
  info "steps: ${STEPS_TO_RUN[*]}"

  if [[ "$ASSUME_YES" -ne 1 ]] && ! is_dry_run; then
    printf "${Y}continue? [y/N]${NC} "
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "aborted."; exit 0; }
  fi
  echo ""

  local step
  for step in "${STEPS_TO_RUN[@]}"; do
    "step_$step"
  done

  echo ""
  ok "done — log out and run 'startx', or 'source ~/.bashrc' for the shell only"
}

# Allow tests to source this file for parse_args without running main.
if [[ -z "${INSTALL_SOURCED_FOR_TEST:-}" ]]; then
  main "$@"
fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/install_args.bats`
Expected: 8 tests, all PASS.

- [ ] **Step 5: Exercise the dry run**

```bash
./install.sh --dry-run --yes 2>&1 | tee /tmp/dryrun.log
grep -c 'dry-run' /tmp/dryrun.log
```

Expected: exits 0, and every mutating action is announced rather than performed. Read the log against the spec's link map and confirm the destinations are right before proceeding.

- [ ] **Step 6: Confirm the dry run really changed nothing**

```bash
./install.sh --dry-run --yes >/dev/null 2>&1
ls ~/.config/nvim -ld
git -C "$REPO_ROOT" status --porcelain
```

Expected: `~/.config/nvim` is still whatever it was before (not yet a symlink — Task 15 does the real migration), and the repo is clean.

- [ ] **Step 7: Lint and commit**

```bash
shellcheck -S warning install.sh
git add install.sh tests/install_args.bats
git commit -m "feat: rewrite install.sh against the real repo layout

The previous script targeted ~/.dotfiles with a directory structure that
never existed in this repo, so every config step hit a silent 'skipping'
branch and it still reported success. This version is Arch-only, honours
--dry-run, and ends with a verify step that exits non-zero when anything
is missing."
```

---

### Task 11: sync.sh

**Files:**
- Create: `sync.sh`

**Interfaces:**
- Consumes: `lib/log.sh`, `lib/link.sh`
- Produces: a reporting/`--apply` tool for the paths that are copied rather than symlinked.

- [ ] **Step 1: Write sync.sh**

```bash
#!/usr/bin/env bash
# Pull machine state back into the repo for the things install.sh copies
# rather than symlinks. After the symlink migration this should report no
# config differences at all — that it reports none is the evidence the
# migration worked.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT

# shellcheck source=lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=lib/link.sh
source "$REPO_ROOT/lib/link.sh"

APPLY=0
DRY_RUN=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

sync_packages() {
  local out="$REPO_ROOT/packages/snapshot.txt"
  local tmp
  tmp="$(mktemp)"
  {
    echo "# Full package snapshot of the origin machine."
    echo "# Generated $(date -I) by sync.sh. Consumed by ./install.sh --full"
    echo
    echo "# ── native, explicitly installed ──"
    pacman -Qqen
    echo
    echo "# ── foreign (AUR) ──"
    pacman -Qqem
  } > "$tmp"

  if diff -q "$tmp" "$out" &>/dev/null; then
    ok "package snapshot unchanged"
  elif [[ "$APPLY" -eq 1 ]]; then
    mv "$tmp" "$out"
    ok "package snapshot updated"
    return 0
  else
    warn "package snapshot differs:"
    diff "$out" "$tmp" | head -20 || true
  fi
  rm -f "$tmp"
}

sync_wallpapers() {
  local live="$HOME/Pictures/Wallpapers"
  [[ -d "$live" ]] || { warn "no $live"; return 0; }
  local new
  new="$(diff <(ls "$REPO_ROOT/Wallpapers") <(ls "$live") | grep '^>' || true)"
  if [[ -z "$new" ]]; then
    ok "wallpapers unchanged"
  elif [[ "$APPLY" -eq 1 ]]; then
    rsync -a "$live/" "$REPO_ROOT/Wallpapers/"
    ok "wallpapers pulled in"
  else
    warn "wallpapers present on the machine but not in the repo:"
    echo "$new"
  fi
}

check_links() {
  if verify_links; then
    ok "all config paths are symlinks into this repo — no drift possible"
  else
    warn "some paths are not linked; run ./install.sh --only link"
  fi
}

log "syncing machine state -> repo"
[[ "$APPLY" -eq 1 ]] || info "reporting only; pass --apply to write changes"
echo ""
check_links
sync_packages
sync_wallpapers
echo ""
ok "sync complete"
```

- [ ] **Step 2: Run it in report mode**

```bash
./sync.sh
```

Expected: exits 0. Before Task 15 it will report that paths are not yet linked — that is correct at this point.

- [ ] **Step 3: Confirm report mode wrote nothing**

```bash
git status --porcelain
```

Expected: no output.

- [ ] **Step 4: Lint and commit**

```bash
shellcheck -S warning sync.sh
chmod +x sync.sh install.sh
git add sync.sh install.sh
git commit -m "feat: add sync.sh for machine -> repo reporting"
```

---

### Task 12: Documentation

**Files:**
- Rewrite: `README.md`
- Modify: `install.sh` header comment, `index.html` install URL

- [ ] **Step 1: Find and fix the wrong install URL**

The old `install.sh` advertised `https://saeeedhany.github.io/dotfiles/install.sh`, which is a different repo.

```bash
grep -rn 'saeeedhany.github.io' . --include='*.html' --include='*.sh' --include='*.md' \
  | grep -v docs/superpowers
```

Replace every hit with `https://github.com/saeeedhany/ThePrimeSetup.conf`. The repo is cloned, not curl-piped, because `install.sh` needs the rest of the tree.

- [ ] **Step 2: Rewrite README.md**

```markdown
# ThePrimeSetup.conf

Arch Linux + dwm / st / dmenu, driven from the terminal. Everything here
installs with one command on a fresh machine.

## Install

```bash
git clone https://github.com/saeeedhany/ThePrimeSetup.conf
cd ThePrimeSetup.conf
./install.sh
```

Arch only. Preview what it would do first with `./install.sh --dry-run`.

```
--only  a,b,c   run only these steps
--skip  a,b,c   run everything except these steps
--full          install the exact package set of the origin machine
--dry-run       print every action without performing it
--yes           do not prompt

steps: preflight packages aur link suckless fonts wallpapers verify
```

## What it does

| Step | Effect |
|---|---|
| `preflight` | Asserts Arch, non-root, sudo, network |
| `packages` | `packages/pacman.txt` (or `snapshot.txt` with `--full`) |
| `aur` | Bootstraps `yay`, installs `packages/aur.txt` |
| `link` | Symlinks `config/`, `home/`, `bin/` and `suckless/` into place |
| `suckless` | Compiles and installs dwm, st, dmenu, dwmblocks |
| `fonts` | Refreshes the font cache |
| `wallpapers` | Copies `Wallpapers/` to `~/Pictures/Wallpapers` |
| `verify` | Fails loudly if any link, binary or font is missing |

Anything already at a destination is moved to `<path>.bak.<timestamp>`
before being replaced. Re-running is safe and makes no changes.

## Layout

```
config/     -> ~/.config/<name>      nvim, tmux, dunst, picom, sxhkd, zathura, dwmblocks
home/       -> ~/<dotfile>           bashrc, bash_profile, xinitrc, xprofile
bin/        -> ~/.local/bin/         battery-monitor, deasy, study
suckless/   -> ~/.config/suckless    dwm, st, dmenu, dwmblocks sources
packages/                            curated lists + full machine snapshot
Wallpapers/                          copied, not linked
```

Because `config/` and `suckless/` are symlinked rather than copied, editing
a config in its usual place edits this repo. Drift is not possible.

## Per-machine overrides

`~/.config/dotfiles/local.sh` is sourced by `xinitrc` if it exists and is
never committed. Put monitor layouts and per-host environment there.

The second monitor (`xrandr --output HDMI-1-0 --mode 2560x1440 --rate 144`)
only runs when that output is connected, and the nvidia status blocks
short-circuit when `nvidia-smi` is absent.

## Keeping the repo current

```bash
./sync.sh           # report drift
./sync.sh --apply   # pull machine state in
```

## Note on dwmblocks

The dwmblocks source was lost; only the compiled binary and its scripts
survived. `suckless/dwmblocks/blocks.def.h` was reconstructed by decoding
the `blocks[]` array out of that binary, and verified by rebuilding and
diffing `.rodata` against the original. Every icon, command and interval is
exact. The single unverified value is `delimLen`, set to upstream's 5 for a
3-character delimiter; it is a buffer stride and renders identically.

The status bar icons need a Nerd Font, which is why `ttf-0xproto-nerd` is a
hard dependency rather than a cosmetic one.

## Docs

- [Bash configuration manual](docs/bash.md)
- [Tmux configuration manual](docs/tmux.md)
```

- [ ] **Step 3: Verify every path the README claims actually exists**

```bash
for p in config home bin suckless packages Wallpapers docs/bash.md docs/tmux.md \
         install.sh sync.sh; do
  [ -e "$p" ] || echo "README references a missing path: $p"
done
echo "README path check done"
```

Expected: no missing-path lines.

- [ ] **Step 4: Commit**

```bash
git add README.md install.sh index.html
git commit -m "docs: rewrite README for the new layout, fix install URL"
```

---

### Task 13: Clean-machine integration test

This is what substantiates "works on a fresh machine". Without it, the claim is exactly the one the old `install.sh` made falsely.

**Files:**
- Create: `tests/Dockerfile`, `tests/integration.sh`

- [ ] **Step 1: Write tests/Dockerfile**

```dockerfile
FROM archlinux:base-devel

# A non-root user, because install.sh refuses to run as root.
RUN pacman -Sy --noconfirm --needed sudo git \
 && useradd -m -G wheel tester \
 && echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel

USER tester
WORKDIR /home/tester/ThePrimeSetup.conf
COPY --chown=tester:tester . .

CMD ["bash", "tests/integration.sh"]
```

- [ ] **Step 2: Write tests/integration.sh**

```bash
#!/usr/bin/env bash
# Runs inside the container from tests/Dockerfile. Exercises every step
# that can work headless. The X session cannot start and the GPU blocks
# have no device, so 'wallpapers' is included but the session is not.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== unit tests ==="
bats tests/

echo "=== shellcheck ==="
shellcheck -S warning install.sh sync.sh lib/*.sh tests/integration.sh

echo "=== dry run ==="
./install.sh --dry-run --yes

echo "=== real install (no AUR: no network guarantees in CI) ==="
./install.sh --yes --skip aur

echo "=== assert links ==="
for p in ~/.config/nvim ~/.config/tmux ~/.config/suckless ~/.bashrc ~/.xinitrc; do
  [ -L "$p" ] || { echo "FAIL: $p is not a symlink"; exit 1; }
  [ -e "$p" ] || { echo "FAIL: $p is a broken symlink"; exit 1; }
done

echo "=== assert binaries ==="
for b in dwm st dmenu dwmblocks; do
  command -v "$b" >/dev/null || { echo "FAIL: $b not installed"; exit 1; }
done

echo "=== assert idempotency ==="
# A second run must create no new backups: if it does, link_one is failing
# to recognise its own work. Count into a variable rather than piping into
# a while loop, where 'exit 1' would only leave the subshell.
touch /tmp/idempotency-marker
./install.sh --yes --skip aur
new_backups="$(find "$HOME" -maxdepth 4 -name '*.bak.*' \
                 -newer /tmp/idempotency-marker | wc -l)"
if [ "$new_backups" -ne 0 ]; then
  echo "FAIL: second run created $new_backups backup(s):"
  find "$HOME" -maxdepth 4 -name '*.bak.*' -newer /tmp/idempotency-marker
  exit 1
fi

echo "=== ALL INTEGRATION CHECKS PASSED ==="
```

The idempotency assertion is the important one: a second run that creates
backups means `link_one` is not detecting its own work.

- [ ] **Step 3: Build the image**

```bash
docker build -f tests/Dockerfile -t theprimesetup-test .
```

Expected: builds successfully.

- [ ] **Step 4: Run the integration test**

```bash
docker run --rm theprimesetup-test
```

Expected: ends with `=== ALL INTEGRATION CHECKS PASSED ===` and exit 0.

If `bats` or `shellcheck` are missing in the container, add them to the
`pacman -Sy` line in the Dockerfile and rebuild — do not skip the checks.

- [ ] **Step 5: Prove the verify step actually fails when something is wrong**

A verification that cannot fail is worthless. Break a link deliberately:

```bash
docker run --rm theprimesetup-test bash -c '
  ./install.sh --yes --skip aur >/dev/null 2>&1
  rm ~/.config/nvim
  if ./install.sh --only verify --yes; then
    echo "FAIL: verify passed with a missing link"; exit 1
  else
    echo "OK: verify correctly rejected a missing link"
  fi'
```

Expected: `OK: verify correctly rejected a missing link`.

- [ ] **Step 6: Commit**

```bash
git add tests/Dockerfile tests/integration.sh
git commit -m "test: add clean-machine integration test in Docker

Runs the installer end to end on a bare Arch image and asserts links,
binaries, idempotency, and that verify actually fails when a link is
missing."
```

---

### Task 14: Migrate the live machine

Everything so far has been built and tested without touching the user's working setup. This task performs the real migration.

- [ ] **Step 1: Take a safety snapshot first**

```bash
SNAP="$HOME/dotfiles-premigration-$(date +%s).tar.gz"
tar czf "$SNAP" \
  -C "$HOME" .bashrc .bash_profile .xinitrc .xprofile \
  .config/nvim .config/tmux .config/dunst .config/picom \
  .config/sxhkd .config/zathura .config/dwmblocks .config/suckless \
  2>/dev/null
echo "snapshot: $SNAP"
ls -lh "$SNAP"
```

Report the snapshot path to the user before continuing. `install.sh` makes
its own per-file backups, but a single archive is easier to roll back from.

- [ ] **Step 2: Dry run and read the output**

```bash
./install.sh --dry-run --yes
```

Confirm every destination matches the spec's link map before doing anything
real.

- [ ] **Step 3: Migrate configuration only, leaving packages alone**

```bash
./install.sh --yes --only link
```

Expected: each destination is backed up to `.bak.<ts>` and replaced with a
symlink into the repo.

- [ ] **Step 4: Verify the links and that content is unchanged**

```bash
./install.sh --only verify --yes
for p in ~/.bashrc ~/.xinitrc ~/.config/nvim ~/.config/suckless; do
  printf '%-28s -> %s\n' "$p" "$(readlink -f "$p")"
done
diff -r ~/.config/nvim.bak.* ~/.config/nvim && echo "nvim content identical"
```

Expected: verification passes, every path resolves into the repo, and the
nvim diff is empty. A non-empty diff here means Task 4 pulled in the wrong
content — stop and investigate rather than proceeding.

- [ ] **Step 5: Rebuild and reinstall the suckless tools from the repo**

```bash
./install.sh --yes --only suckless
```

Expected: all four build and install. `dwmblocks` is now built from the
reconstructed source rather than being the orphaned binary.

- [ ] **Step 6: Confirm the running desktop still works**

This needs the user. Ask them to:

1. Open a new `st` window — the font and Gruvbox colours should be unchanged.
2. Press `Super+p` (or their dmenu binding) — dmenu should appear centred.
3. Check the status bar — all nine blocks should render with icons, no boxes
   or `N/A` where a value is expected.
4. Restart X (log out, `startx`) and confirm dwm comes back with the second
   monitor positioned as before.

Do not mark this task complete on the basis of the scripts alone. If the bar
shows tofu boxes instead of icons, `ttf-0xproto-nerd` did not install — run
`./install.sh --only packages --yes`.

- [ ] **Step 7: Confirm sync.sh now reports no drift**

```bash
./sync.sh
```

Expected: `all config paths are symlinks into this repo — no drift possible`.
This is the goal condition of the whole plan.

- [ ] **Step 8: Clean up backups once the user confirms everything works**

Only after Step 6 is confirmed by the user:

```bash
ls -d ~/.config/*.bak.* ~/*.bak.* 2>/dev/null
```

Show this list and ask before deleting anything. Keep the tarball from
Step 1 regardless.

- [ ] **Step 9: Final commit**

```bash
git add -A
git commit -m "chore: complete migration to symlinked dotfiles"
git log --oneline | head -20
```

---

## Verification Summary

The plan is complete when all of these hold:

| Check | Command | Expected |
|---|---|---|
| Unit tests | `bats tests/` | all pass |
| Lint | `shellcheck -S warning install.sh sync.sh lib/*.sh` | clean |
| Clean-machine install | `docker run --rm theprimesetup-test` | `ALL INTEGRATION CHECKS PASSED` |
| Verify can fail | Task 13 Step 5 | rejects a missing link |
| Idempotent | second `./install.sh --yes` | no new `.bak.*` files |
| dwmblocks exact | Task 6 Step 5 | `RODATA IDENTICAL` |
| No drift | `./sync.sh` | all paths symlinked |
| Desktop works | Task 14 Step 6 | user confirms |

Do not report the work complete until the Docker run and the user's desktop
confirmation have both actually happened. The defect this plan exists to fix
was a script that claimed success without doing anything.
