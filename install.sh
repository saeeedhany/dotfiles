#!/usr/bin/env bash
# saeeedhany/dotfiles — bootstrap installer
# usage: bash <(curl -fsSL https://saeeedhany.github.io/dotfiles/install.sh)
set -euo pipefail

# ── colors ─────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'
B='\033[0;34m'; C='\033[0;36m'; D='\033[0;90m'
W='\033[0;37m'; BOLD='\033[1m'; NC='\033[0m'

log()  { printf "${D}[${NC}${G}+${NC}${D}]${NC} %s\n" "$*"; }
info() { printf "${D}[${NC}${B}*${NC}${D}]${NC} %s\n" "$*"; }
warn() { printf "${D}[${NC}${Y}!${NC}${D}]${NC} %s\n" "$*"; }
die()  { printf "${D}[${NC}${R}✗${NC}${D}]${NC} %s\n" "$*"; exit 1; }
ok()   { printf "${D}[${NC}${C}✓${NC}${D}]${NC} %s\n" "$*"; }

banner() {
  printf "\n${D}┌─────────────────────────────────────────┐${NC}\n"
  printf "${D}│${NC}  ${BOLD}~${NC}${B}/saeeedhany${NC} — environment bootstrap  ${D}│${NC}\n"
  printf "${D}└─────────────────────────────────────────┘${NC}\n\n"
}

# ── detect distro ──────────────────────────────────────────────────────────
detect_distro() {
  if command -v pacman &>/dev/null; then
    DISTRO="arch"
    PKG_INSTALL="sudo pacman -S --needed --noconfirm"
    PKG_UPDATE="sudo pacman -Syu --noconfirm"
  elif command -v apt-get &>/dev/null; then
    DISTRO="debian"
    PKG_INSTALL="sudo apt-get install -y"
    PKG_UPDATE="sudo apt-get update -qq && sudo apt-get upgrade -y"
  elif command -v dnf &>/dev/null; then
    DISTRO="fedora"
    PKG_INSTALL="sudo dnf install -y"
    PKG_UPDATE="sudo dnf upgrade -y"
  else
    die "unsupported distro — only arch, debian/ubuntu, and fedora are supported."
  fi
  info "detected: ${BOLD}$DISTRO${NC}"
}

# ── package names by distro ────────────────────────────────────────────────
pkg() {
  # pkg arch debian fedora
  local arch="$1" debian="$2" fedora="$3"
  case "$DISTRO" in
    arch)   echo "$arch"   ;;
    debian) echo "$debian" ;;
    fedora) echo "$fedora" ;;
  esac
}

# ── helpers ────────────────────────────────────────────────────────────────
need() { command -v "$1" &>/dev/null || return 1; }

ensure_yay() {
  if [[ "$DISTRO" == "arch" ]] && ! command -v yay &>/dev/null; then
    log "installing yay (AUR helper)..."
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git /tmp/yay-build
    (cd /tmp/yay-build && makepkg -si --noconfirm)
    rm -rf /tmp/yay-build
    AUR_INSTALL="yay -S --needed --noconfirm"
  elif [[ "$DISTRO" == "arch" ]]; then
    AUR_INSTALL="yay -S --needed --noconfirm"
  fi
}

# ── steps ──────────────────────────────────────────────────────────────────

step_update() {
  log "updating package index..."
  eval "$PKG_UPDATE" &>/dev/null
  ok "packages up to date"
}

step_base_deps() {
  log "installing base dependencies..."
  local pkgs=(
    "$(pkg git git git)"
    "$(pkg base-devel build-essential '@Development Tools')"
    "$(pkg curl curl curl)"
    "$(pkg wget wget wget)"
    "$(pkg unzip unzip unzip)"
    "$(pkg ripgrep ripgrep ripgrep)"
    "$(pkg fd fd-find fd-find)"
    "$(pkg xclip xclip xclip)"
  )
  $PKG_INSTALL "${pkgs[@]}" &>/dev/null
  ok "base deps installed"
}

step_clone_dotfiles() {
  DOTFILES="$HOME/.dotfiles"
  if [[ -d "$DOTFILES" ]]; then
    warn "~/.dotfiles already exists — pulling latest..."
    git -C "$DOTFILES" pull --ff-only
  else
    log "cloning dotfiles..."
    git clone --depth=1 https://github.com/saeeedhany/dotfiles.git "$DOTFILES"
  fi
  ok "dotfiles at $DOTFILES"
}

step_neovim() {
  if need nvim; then
    warn "neovim already installed — skipping"
    return
  fi
  log "installing neovim..."
  case "$DISTRO" in
    arch)   $PKG_INSTALL neovim &>/dev/null ;;
    debian)
      # get latest appimage for debian since repos lag
      curl -fsSL -o /tmp/nvim.appimage \
        "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage"
      chmod +x /tmp/nvim.appimage
      sudo mv /tmp/nvim.appimage /usr/local/bin/nvim
      ;;
    fedora) $PKG_INSTALL neovim &>/dev/null ;;
  esac

  log "symlinking nvim config..."
  mkdir -p "$HOME/.config"
  [[ -d "$HOME/.config/nvim" ]] && mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak.$(date +%s)"
  ln -sf "$DOTFILES/.config/nvim" "$HOME/.config/nvim"
  ok "neovim configured (lazy.nvim will auto-install plugins on first launch)"
}

step_suckless() {
  log "installing suckless build deps..."
  local xlibs
  case "$DISTRO" in
    arch)   xlibs="libx11 libxinerama libxft" ;;
    debian) xlibs="libx11-dev libxinerama-dev libxft-dev libxrandr-dev" ;;
    fedora) xlibs="libX11-devel libXinerama-devel libXft-devel libXrandr-devel" ;;
  esac
  $PKG_INSTALL $xlibs &>/dev/null

  SUCKLESS_SRC="$HOME/src/suckless"
  mkdir -p "$SUCKLESS_SRC"

  for tool in dwm st dmenu slstatus; do
    local src_dir="$SUCKLESS_SRC/$tool"
    if [[ -d "$DOTFILES/suckless/$tool" ]]; then
      log "building $tool from dotfiles..."
      rsync -a "$DOTFILES/suckless/$tool/" "$src_dir/"
    else
      warn "$tool not found in dotfiles/suckless/ — skipping"
      continue
    fi
    (
      cd "$src_dir"
      make &>/dev/null
      sudo make install &>/dev/null
    )
    ok "$tool compiled and installed"
  done
}

step_shell() {
  log "setting up bash config..."
  [[ -f "$HOME/.bashrc" ]] && cp "$HOME/.bashrc" "$HOME/.bashrc.bak.$(date +%s)"
  ln -sf "$DOTFILES/.bashrc" "$HOME/.bashrc"

  [[ -f "$DOTFILES/.bash_profile" ]] && ln -sf "$DOTFILES/.bash_profile" "$HOME/.bash_profile"
  [[ -f "$DOTFILES/.profile" ]]      && ln -sf "$DOTFILES/.profile" "$HOME/.profile"
  ok "bash configured"
}

step_fonts() {
  log "installing fonts..."
  case "$DISTRO" in
    arch)   $PKG_INSTALL ttf-jetbrains-mono nerd-fonts-jetbrains-mono &>/dev/null 2>&1 || true ;;
    debian|fedora)
      mkdir -p "$HOME/.local/share/fonts"
      curl -fsSL -o /tmp/jbmono.zip \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
      unzip -o /tmp/jbmono.zip -d "$HOME/.local/share/fonts/" &>/dev/null
      fc-cache -f "$HOME/.local/share/fonts" &>/dev/null
      rm /tmp/jbmono.zip
      ;;
  esac
  ok "JetBrainsMono Nerd Font installed"
}

step_x11() {
  log "setting up X11 config (.xinitrc, .xresources)..."
  [[ -f "$DOTFILES/.xinitrc" ]]   && ln -sf "$DOTFILES/.xinitrc"   "$HOME/.xinitrc"
  [[ -f "$DOTFILES/.Xresources" ]] && ln -sf "$DOTFILES/.Xresources" "$HOME/.Xresources"
  [[ -f "$HOME/.Xresources" ]]    && xrdb -merge "$HOME/.Xresources" 2>/dev/null || true
  ok "X11 config linked"
}

step_scripts() {
  log "linking scripts to ~/bin..."
  mkdir -p "$HOME/bin"
  if [[ -d "$DOTFILES/bin" ]]; then
    for f in "$DOTFILES/bin/"*; do
      ln -sf "$f" "$HOME/bin/$(basename "$f")"
      chmod +x "$f"
    done
    ok "scripts linked to ~/bin"
  else
    warn "no bin/ directory in dotfiles — skipping"
  fi
}

step_misc_tools() {
  log "installing misc tools..."
  local pkgs=(
    "$(pkg htop htop htop)"
    "$(pkg feh feh feh)"
    "$(pkg picom picom picom)"
    "$(pkg dunst dunst dunst)"
    "$(pkg maim maim maim)"
    "$(pkg xdotool xdotool xdotool)"
  )
  $PKG_INSTALL "${pkgs[@]}" &>/dev/null 2>&1 || true
  ok "misc tools installed"
}

# ── main ───────────────────────────────────────────────────────────────────
main() {
  banner
  detect_distro
  [[ "$DISTRO" == "arch" ]] && ensure_yay

  echo ""
  printf "${BOLD}steps:${NC}\n"
  printf "  ${D}1${NC} update packages\n"
  printf "  ${D}2${NC} base deps (git curl ripgrep fd ...)\n"
  printf "  ${D}3${NC} clone ~/.dotfiles\n"
  printf "  ${D}4${NC} neovim + config\n"
  printf "  ${D}5${NC} suckless (dwm st dmenu slstatus) compiled from source\n"
  printf "  ${D}6${NC} bash (.bashrc .bash_profile)\n"
  printf "  ${D}7${NC} fonts (JetBrainsMono Nerd Font)\n"
  printf "  ${D}8${NC} x11 (.xinitrc .Xresources)\n"
  printf "  ${D}9${NC} scripts → ~/bin\n"
  printf "  ${D}10${NC} misc tools (feh picom dunst maim)\n"
  echo ""
  printf "${Y}continue? [y/N]${NC} "
  read -r confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { info "aborted."; exit 0; }
  echo ""

  step_update
  step_base_deps
  step_clone_dotfiles
  step_neovim
  step_suckless
  step_shell
  step_fonts
  step_x11
  step_scripts
  step_misc_tools

  echo ""
  printf "${D}┌──────────────────────────────────────────┐${NC}\n"
  printf "${D}│${NC}  ${G}${BOLD}done.${NC} restart your session or run:       ${D}│${NC}\n"
  printf "${D}│${NC}    ${C}source ~/.bashrc${NC}                        ${D}│${NC}\n"
  printf "${D}│${NC}    ${C}startx${NC}  ${D}# to launch dwm${NC}               ${D}│${NC}\n"
  printf "${D}└──────────────────────────────────────────┘${NC}\n\n"
}

main "$@"
