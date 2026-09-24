#!/usr/bin/env bash
# One-click Neovim + LazyVim setup, then verify it headlessly.
# Based on tonngw/macman "08. 快速配置 Neovim、LazyVim 以及常用开发环境", merged with this repo's
# Markdown setup:
#   1. system packages: Neovim >= 0.11.2, git, curl, wget, unzip, C compiler, ripgrep, fd,
#      lazygit, luarocks, node/npm (+ the npm "neovim" provider), a Nerd Font
#   2. LazyVim starter, only if the config dir is not a LazyVim config yet (old config is backed up)
#   3. LazyVim extras: lang.clangd, lang.json, lang.markdown
#   4. keymaps: ii -> <Esc> (insert), W save, Q quit all, Y copy whole file
#   5. render-markdown: heading icons + signs, checkbox rendering, full-width code blocks with signs
#   6. colorscheme (only with --theme)
#   7. plugins, Mason tools, treesitter parsers, markdown-preview binary
#
# Usage:
#   ./install.sh                 install + verify
#   ./install.sh --theme NAME    also set the colorscheme: gruvbox | everforest | catppuccin | tokyonight
#   ./install.sh --no-deps       skip system packages, only configure Neovim
#   ./install.sh --check         verify only (the script changes nothing; LazyVim itself may
#                                still auto-install missing plugins when nvim starts)
#
# Package managers: apt (Ubuntu/Debian), pacman (Arch), dnf (Fedora), brew (macOS).
set -euo pipefail

EXTRAS=(lazyvim.plugins.extras.lang.clangd lazyvim.plugins.extras.lang.json lazyvim.plugins.extras.lang.markdown)
MASON_PKGS=(tree-sitter-cli marksman markdownlint-cli2 markdown-toc clangd json-lsp)
TS_PARSERS=(markdown markdown_inline c cpp json json5)
STARTER_REPO=https://github.com/LazyVim/starter
NVIM_MIN=0.11.2

CHECK_ONLY=0 NO_DEPS=0 THEME=""
while (($#)); do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --no-deps) NO_DEPS=1 ;;
    --theme)
      THEME="${2:-}"
      shift
      [[ $THEME =~ ^(gruvbox|everforest|catppuccin|tokyonight)$ ]] ||
        { echo "--theme must be one of: gruvbox everforest catppuccin tokyonight" >&2; exit 2; }
      ;;
    -h | --help) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

if [[ -t 1 ]]; then
  C_INFO=$'\e[34m' C_OK=$'\e[32m' C_WARN=$'\e[33m' C_FAIL=$'\e[31m' C_OFF=$'\e[0m'
else
  C_INFO="" C_OK="" C_WARN="" C_FAIL="" C_OFF=""
fi
info() { echo "${C_INFO}==>${C_OFF} $*"; }
warn() { echo "${C_WARN}WARN${C_OFF} $*"; }
die() { echo "${C_FAIL}ERROR${C_OFF} $*" >&2; exit 1; }

WORK=$(mktemp -d)
LOG="$WORK/nvim.log"
trap 'rm -rf "$WORK"' EXIT
STAMP=$(date +%Y%m%d%H%M%S)

# Binaries we download (nvim, lazygit, fd symlink) go here
LOCAL_BIN="$HOME/.local/bin"
ORIG_PATH="$PATH"
export PATH="$LOCAL_BIN:$PATH"

# Run headless nvim with the user's config, logging its noisy output.
nvim_headless() { nvim --headless "$@" >>"$LOG" 2>&1; }
log_tail() { tail -20 "$LOG" | tr '\r' '\n' | grep -v '^\s*$' | tail -10; }
has() { command -v "$1" >/dev/null 2>&1; }
same_file() { [[ -f $1 && -f $2 && $(cksum <"$1") == $(cksum <"$2") ]]; }
nvim_ok() { has nvim && [[ $(nvim --headless --clean +"lua io.write(vim.fn.has('nvim-$NVIM_MIN'))" +qa 2>&1) == 1 ]]; }

as_root() {
  if ((EUID == 0)); then
    "$@"
  elif has sudo; then
    sudo "$@"
  else
    warn "need root (no sudo) for: $*"
    return 1
  fi
}

# ---------------------------------------------------------------- system packages
OS=$(uname -s)
case "$(uname -m)" in
  x86_64 | amd64) ARCH_NVIM=x86_64 ARCH_LG=x86_64 ;;
  aarch64 | arm64) ARCH_NVIM=arm64 ARCH_LG=arm64 ;;
  *) ARCH_NVIM="" ARCH_LG="" ;;
esac

if [[ $OS == Darwin ]]; then
  PM=$(has brew && echo brew || true)
elif has pacman; then
  PM=pacman
elif has apt-get; then
  PM=apt
elif has dnf; then
  PM=dnf
else
  PM=""
fi

# Package providing a command, per package manager ("" = not available there / handled elsewhere)
pkg_for() {
  local cmd=$1
  case "$PM:$cmd" in
    *:git | *:curl | *:wget | *:unzip | *:tar | *:luarocks | *:npm) echo "$cmd" ;;
    apt:xz) echo xz-utils ;;
    *:xz) echo xz ;;
    apt:cc) echo build-essential ;;
    pacman:cc | dnf:cc) echo gcc ;;
    *:rg) echo ripgrep ;;
    apt:fd | dnf:fd) echo fd-find ;;
    pacman:fd | brew:fd) echo fd ;;
    apt:lazygit | pacman:lazygit | brew:lazygit) echo lazygit ;;
    brew:node) echo node ;;
    *:node) echo nodejs ;;
    pacman:nvim | brew:nvim | dnf:nvim) echo neovim ;;
    *) ;;
  esac
}

pm_install() {
  (($#)) || return 0
  info "Installing with $PM: $*"
  case "$PM" in
    apt)
      as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq &&
        as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ca-certificates "$@"
      ;;
    pacman) as_root pacman -Syu --needed --noconfirm "$@" ;;
    dnf) as_root dnf install -y -q "$@" ;;
    brew) brew install "$@" ;;
  esac
}

# Latest GitHub release tag (e.g. v0.55.1) via the /releases/latest redirect
gh_latest_tag() { curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's#.*/tag/##'; }

install_nvim_tarball() {
  [[ -n $ARCH_NVIM ]] || { warn "no prebuilt Neovim for $(uname -m)"; return 1; }
  local name="nvim-linux-$ARCH_NVIM" dest="$HOME/.local/opt"
  info "Downloading Neovim release $name.tar.gz"
  mkdir -p "$dest" "$LOCAL_BIN"
  curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/$name.tar.gz" -o "$WORK/nvim.tar.gz" || return 1
  rm -rf "${dest:?}/$name"
  tar -xzf "$WORK/nvim.tar.gz" -C "$dest"
  ln -sf "$dest/$name/bin/nvim" "$LOCAL_BIN/nvim"
  hash -r
}

install_lazygit_release() {
  [[ -n $ARCH_LG ]] || return 1
  local tag ver os
  tag=$(gh_latest_tag jesseduffield/lazygit) || return 1
  ver=${tag#v}
  info "Downloading lazygit $tag"
  for os in Linux linux; do
    curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/$tag/lazygit_${ver}_${os}_${ARCH_LG}.tar.gz" \
      -o "$WORK/lazygit.tar.gz" 2>/dev/null && break
  done
  [[ -s $WORK/lazygit.tar.gz ]] || return 1
  mkdir -p "$LOCAL_BIN"
  tar -xzf "$WORK/lazygit.tar.gz" -C "$LOCAL_BIN" lazygit
}

has_nerd_font() {
  if [[ $OS == Darwin ]]; then
    compgen -G "$HOME/Library/Fonts/*Nerd*" >/dev/null || compgen -G "/Library/Fonts/*Nerd*" >/dev/null
  else
    fc-list 2>/dev/null | grep -i nerd >/dev/null # not -q: early exit would SIGPIPE fc-list under pipefail
  fi
}

install_nerd_font() {
  case "$PM" in
    brew) brew install --cask font-jetbrains-mono-nerd-font ;;
    pacman) pm_install ttf-jetbrains-mono-nerd ;;
    *)
      local dir="$HOME/.local/share/fonts/JetBrainsMonoNerd"
      info "Downloading JetBrainsMono Nerd Font to $dir"
      mkdir -p "$dir"
      curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz |
        tar -xJf - -C "$dir" && fc-cache -f "$dir" >/dev/null
      ;;
  esac
}

if ((!CHECK_ONLY && !NO_DEPS)); then
  [[ -n $PM ]] || die "no supported package manager (apt/pacman/dnf, or Homebrew on macOS); rerun with --no-deps"
  [[ $OS == Darwin ]] && ! xcode-select -p >/dev/null 2>&1 && warn "no Xcode Command Line Tools: run 'xcode-select --install' for a C compiler"

  missing=()
  for cmd in git curl wget unzip tar xz cc rg fd lazygit luarocks node npm; do
    [[ $cmd == fd ]] && has fdfind && continue
    [[ $cmd == cc && $OS == Darwin ]] && continue
    has "$cmd" && continue
    pkg=$(pkg_for "$cmd")
    [[ -n $pkg && " ${missing[*]-} " != *" $pkg "* ]] && missing+=("$pkg")
  done
  # apt/dnf ship old Neovim on LTS releases: those get the official tarball below instead
  if ! nvim_ok && [[ $PM == pacman || $PM == brew ]]; then
    missing+=(neovim)
  fi
  if ((${#missing[@]})); then
    pm_install "${missing[@]}" || warn "some packages failed to install (checked again at the end)"
  else
    info "System packages already present"
  fi

  if ! nvim_ok; then
    if [[ $OS == Linux ]]; then
      install_nvim_tarball || warn "Neovim download failed"
    elif [[ $PM == brew ]]; then
      brew upgrade neovim || true
    fi
  fi

  # Debian/Ubuntu name the fd binary fdfind
  if ! has fd && has fdfind; then
    mkdir -p "$LOCAL_BIN" && ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
  fi
  if ! has lazygit && [[ $OS == Linux ]]; then
    install_lazygit_release || warn "lazygit download failed"
  fi

  # npm "neovim" package: node provider for :checkhealth
  if has npm; then
    if npm ls -g --depth=0 neovim >/dev/null 2>&1; then
      info "npm package 'neovim' already installed"
    else
      info "Installing npm package 'neovim'"
      npm install -g neovim >>"$LOG" 2>&1 || as_root npm install -g neovim >>"$LOG" 2>&1 ||
        warn "npm install -g neovim failed"
    fi
  fi

  if has_nerd_font; then
    info "Nerd Font already installed"
  elif [[ $OS == Darwin ]] || has fc-list; then
    install_nerd_font || warn "Nerd Font install failed"
    info "Set your terminal font to 'JetBrainsMono Nerd Font' so icons render"
  else
    info "No fontconfig here (server/container?): install a Nerd Font on the machine running your terminal"
  fi
fi

# ---------------------------------------------------------------- preflight
has nvim || die "nvim not found in PATH"
nvim_ok || die "LazyVim needs Neovim >= $NVIM_MIN (found: $(nvim --version | head -1))"

CONFIG_DIR=$(nvim --headless --clean +'lua io.write(vim.fn.stdpath("config"))' +qa 2>&1)
DATA_DIR=$(nvim --headless --clean +'lua io.write(vim.fn.stdpath("data"))' +qa 2>&1)
STATE_DIR=$(nvim --headless --clean +'lua io.write(vim.fn.stdpath("state"))' +qa 2>&1)
CACHE_DIR=$(nvim --headless --clean +'lua io.write(vim.fn.stdpath("cache"))' +qa 2>&1)
LAZYVIM_JSON="$CONFIG_DIR/lazyvim.json"
KEYMAPS="$CONFIG_DIR/lua/config/keymaps.lua"
RM_OVERRIDE="$CONFIG_DIR/lua/plugins/render-markdown.lua"
THEME_FILE="$CONFIG_DIR/lua/plugins/colorscheme.lua"

is_lazyvim() { grep -rqs 'LazyVim/LazyVim' "$CONFIG_DIR/init.lua" "$CONFIG_DIR/lua"; }

# Write $2 (a temp file) to $1 unless identical; back up a differing existing file
install_file() {
  local dest=$1 src=$2
  if same_file "$dest" "$src"; then
    info "Up to date: $dest"
    return
  fi
  mkdir -p "$(dirname "$dest")"
  ((!FRESH)) && [[ -f $dest ]] && cp "$dest" "$dest.bak.$STAMP" && info "Backed up $dest -> $dest.bak.$STAMP"
  cp "$src" "$dest"
  info "Wrote $dest"
}

# ---------------------------------------------------------------- configure
if ((!CHECK_ONLY)); then
  has git || die "git is required"

  # 1. LazyVim starter (article: back up the old config, clone the starter, drop its .git)
  FRESH=0
  if is_lazyvim; then
    info "LazyVim config: $CONFIG_DIR"
  else
    if [[ -d $CONFIG_DIR ]] && [[ -n $(ls -A "$CONFIG_DIR") ]]; then
      for d in "$CONFIG_DIR" "$DATA_DIR" "$STATE_DIR" "$CACHE_DIR"; do
        [[ -e $d ]] && mv "$d" "$d.bak.$STAMP" && info "Backed up $d -> $d.bak.$STAMP"
      done
    fi
    info "Cloning LazyVim starter into $CONFIG_DIR"
    git clone -q --depth 1 "$STARTER_REPO" "$CONFIG_DIR"
    rm -rf "$CONFIG_DIR/.git"
    FRESH=1
  fi

  # 2. Keymaps from the article, kept in a marked block so reruns replace instead of duplicating
  BEGIN_MARK="-- >>> install.sh keymaps (managed by install.sh, edits inside this block are overwritten)"
  END_MARK="-- <<< install.sh keymaps"
  mkdir -p "$(dirname "$KEYMAPS")"
  touch "$KEYMAPS"
  {
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$KEYMAPS" |
      sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
    cat <<EOF

$BEGIN_MARK
vim.keymap.set("i", "ii", "<Esc>", { desc = "Exit insert mode" })
vim.keymap.set("n", "W", "<cmd>w<cr>", { desc = "Save file" })
vim.keymap.set("n", "Q", "<cmd>qa<cr>", { desc = "Quit all" })
vim.keymap.set("n", "Y", "<cmd>%y<cr>", { desc = "Copy entire file" })
$END_MARK
EOF
  } >"$WORK/keymaps.lua"
  install_file "$KEYMAPS" "$WORK/keymaps.lua"

  # 3. render-markdown override
  cat >"$WORK/render-markdown.lua" <<'EOF'
-- Override LazyVim lang.markdown extra: show heading icons, render checkboxes, full-width code blocks
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      heading = {
        sign = true,
        icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
      },
      checkbox = {
        enabled = true,
      },
      code = {
        sign = true,
        width = "full",
      },
    },
  },
}
EOF
  install_file "$RM_OVERRIDE" "$WORK/render-markdown.lua"

  # 4. Colorscheme (opt-in: many configs manage their theme elsewhere)
  if [[ -n $THEME ]]; then
    case "$THEME" in
      gruvbox) plugin='{ "ellisonleao/gruvbox.nvim" },' ;;
      everforest)
        plugin='{
    "neanias/everforest-nvim",
    version = false,
    lazy = false,
    priority = 1000,
    config = function()
      require("everforest").setup({})
    end,
  },' ;;
      *) plugin="" ;; # catppuccin and tokyonight are bundled with LazyVim
    esac
    {
      echo "-- Colorscheme (written by install.sh --theme $THEME)"
      echo "return {"
      [[ -n $plugin ]] && echo "  $plugin"
      echo "  { \"LazyVim/LazyVim\", opts = { colorscheme = \"$THEME\" } },"
      echo "}"
    } >"$WORK/colorscheme.lua"
    install_file "$THEME_FILE" "$WORK/colorscheme.lua"
    [[ -e $CONFIG_DIR/lua/plugins/theme.lua ]] &&
      warn "lua/plugins/theme.lua exists (Omarchy?) and may override the colorscheme"
  fi

  # 5. Plugins: first pass bootstraps lazy.nvim + LazyVim
  info "Installing plugins with lazy.nvim (may take a while on a fresh machine)..."
  nvim_headless "+Lazy! install" +qa || die "lazy.nvim install failed:"$'\n'"$(log_tail)"

  # 6. Enable extras through LazyVim's own lazyvim.json writer (same as :LazyExtras)
  [[ -f $LAZYVIM_JSON ]] && cp "$LAZYVIM_JSON" "$WORK/lazyvim.json.orig"
  cat >"$WORK/extras.lua" <<'EOF'
local out = assert(io.open(vim.env.EXTRAS_OUT, "w"))
local json = LazyVim.config.json
json.data.extras = json.data.extras or {}
for _, extra in ipairs(vim.split(vim.env.EXTRAS, " ")) do
  if vim.tbl_contains(json.data.extras, extra) then
    out:write("already enabled\t" .. extra .. "\n")
  else
    table.insert(json.data.extras, extra)
    out:write("enabled\t" .. extra .. "\n")
  end
end
LazyVim.json.save()
out:close()
vim.cmd("qa!")
EOF
  EXTRAS="${EXTRAS[*]}" EXTRAS_OUT="$WORK/extras.out" nvim_headless "+luafile $WORK/extras.lua" || true
  [[ -s $WORK/extras.out ]] || die "enabling extras failed:"$'\n'"$(log_tail)"
  while IFS=$'\t' read -r status extra; do info "  $extra: $status"; done <"$WORK/extras.out"
  if [[ -f $WORK/lazyvim.json.orig ]] && ! same_file "$WORK/lazyvim.json.orig" "$LAZYVIM_JSON"; then
    cp "$WORK/lazyvim.json.orig" "$LAZYVIM_JSON.bak.$STAMP"
    info "Backed up lazyvim.json -> $LAZYVIM_JSON.bak.$STAMP"
  fi

  # Second pass picks up the plugins the extras added
  nvim_headless "+Lazy! install" +qa || die "lazy.nvim install failed:"$'\n'"$(log_tail)"

  # 7. Mason tools (tree-sitter-cli is needed to build parsers on nvim-treesitter main)
  info "Installing Mason packages: ${MASON_PKGS[*]}"
  cat >"$WORK/mason.lua" <<'EOF'
local names = vim.split(vim.env.MASON_PKGS, " ")
local out = assert(io.open(vim.env.MASON_OUT, "w"))
require("lazy").load({ plugins = { "mason.nvim" } })
local reg = require("mason-registry")
local refreshed = false
reg.refresh(function() refreshed = true end)
vim.wait(120000, function() return refreshed end, 200)

-- LazyVim may already be installing some of these at startup: wait for those
-- instead of starting a second install (Mason asserts on that).
local pkgs, status = {}, {}
for _, name in ipairs(names) do
  local ok, pkg = pcall(reg.get_package, name)
  if not ok then
    status[name] = "unknown package"
  elseif pkg:is_installed() and not pkg:is_installing() then
    status[name] = "already installed"
  else
    pkgs[name] = pkg
    if not pkg:is_installing() then
      local started, err = pcall(pkg.install, pkg, {}, function(success, e)
        if not success then status[name] = tostring(e) end
      end)
      if not started then status[name] = tostring(err) end
    end
  end
end
vim.wait(600000, function()
  for _, pkg in pairs(pkgs) do
    if pkg:is_installing() then return false end
  end
  return true
end, 500)
for _, name in ipairs(names) do
  local pkg = pkgs[name]
  if pkg then
    status[name] = pkg:is_installed() and "installed" or (status[name] or "install failed")
  end
  local ok = status[name] == "installed" or status[name] == "already installed"
  out:write((ok and "OK" or "FAIL") .. "\t" .. name .. "\t" .. status[name] .. "\n")
end
out:close()
vim.cmd("qa!")
EOF
  MASON_PKGS="${MASON_PKGS[*]}" MASON_OUT="$WORK/mason.out" nvim_headless "+luafile $WORK/mason.lua" || true
  [[ -f $WORK/mason.out ]] || die "Mason step did not run:"$'\n'"$(log_tail)"
  while IFS=$'\t' read -r status name detail; do
    if [[ $status == OK ]]; then info "  $name: $detail"; else warn "  $name: $detail"; fi
  done <"$WORK/mason.out"

  # 8. Treesitter parsers
  info "Installing treesitter parsers: ${TS_PARSERS[*]}"
  cat >"$WORK/ts.lua" <<'EOF'
require("lazy").load({ plugins = { "mason.nvim", "nvim-treesitter" } })
local langs = vim.split(vim.env.TS_PARSERS, " ")
local ts = require("nvim-treesitter")
if type(ts.install) == "function" then
  -- nvim-treesitter main branch: async install, wait for it
  local task = ts.install(langs)
  if task and task.wait then task:wait(300000) end
else
  vim.cmd("TSInstallSync " .. table.concat(langs, " ")) -- master branch
end
vim.cmd("qa!")
EOF
  TS_PARSERS="${TS_PARSERS[*]}" nvim_headless "+luafile $WORK/ts.lua" || warn "parser install reported an error (checked again below)"

  # 9. markdown-preview.nvim prebuilt binary. Its lazy build step downloads it
  #    asynchronously, which a headless nvim exits before finishing.
  MKDP_APP="$DATA_DIR/lazy/markdown-preview.nvim/app"
  if compgen -G "$MKDP_APP/bin/markdown-preview-*" >/dev/null; then
    info "markdown-preview binary already present"
  elif [[ -f $MKDP_APP/install.sh ]]; then
    info "Downloading markdown-preview binary..."
    (cd "$MKDP_APP" && bash install.sh) >>"$LOG" 2>&1 || warn "markdown-preview install.sh failed"
  else
    warn "markdown-preview.nvim not installed, skipping binary download"
  fi
fi

# ---------------------------------------------------------------- verify
is_lazyvim || die "$CONFIG_DIR is not a LazyVim config (run without --check to install it)"
info "Verifying $CONFIG_DIR ..."
: >"$WORK/verify.out"
record() { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >>"$WORK/verify.out"; }

# External tools: required ones FAIL, optional ones WARN
for cmd in git curl unzip cc rg fd node npm; do
  if has "$cmd" || { [[ $cmd == fd ]] && has fdfind; }; then record PASS "tool: $cmd"; else record FAIL "tool: $cmd" "not in PATH"; fi
done
for cmd in wget lazygit luarocks; do
  if has "$cmd"; then record PASS "tool: $cmd"; else record WARN "tool: $cmd" "not in PATH"; fi
done
if has_nerd_font; then
  record PASS "Nerd Font installed"
elif [[ $OS == Darwin ]] || has fc-list; then
  record WARN "Nerd Font installed" "icons need a Nerd Font in your terminal"
fi

mkdir -p "$WORK/sample"
SAMPLE="$WORK/sample/sample.md"
cat >"$SAMPLE" <<'EOF'
plain text line (cursor stays here so everything below renders)

# Heading 1

## Heading 2

- [ ] todo
- [x] done

```lua
print("hello")
```
EOF
printf '#include <stdio.h>\n\nint main(void) {\n  printf("hi\\n");\n  return 0;\n}\n' >"$WORK/sample/sample.cpp"
printf '{\n  "name": "sample",\n  "version": "1.0.0"\n}\n' >"$WORK/sample/package.json"
git -C "$WORK/sample" init -q 2>/dev/null || true # gives LSPs a project root

cat >"$WORK/verify.lua" <<'EOF'
local out = assert(io.open(vim.env.VERIFY_OUT, "a"))
local function check(name, ok, detail)
  out:write((ok and "PASS" or "FAIL") .. "\t" .. name .. "\t" .. (detail or "") .. "\n")
end
local function wait_lsp(buf, name, ms)
  return vim.wait(ms, function() return #vim.lsp.get_clients({ bufnr = buf, name = name }) > 0 end, 200)
end

local function run()
  local buf = vim.api.nvim_get_current_buf()
  local data = vim.fn.stdpath("data")

  local lazyvim = vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("config") .. "/lazyvim.json"), "\n"))
  for _, extra in ipairs(vim.split(vim.env.EXTRAS, " ")) do
    check("extra: " .. extra:gsub("^lazyvim%.plugins%.extras%.", ""), vim.tbl_contains(lazyvim.extras or {}, extra))
  end

  -- Neovim bundles some parsers (c, markdown, ...): require nvim-treesitter's own copy under stdpath("data")
  for _, lang in ipairs(vim.split(vim.env.TS_PARSERS, " ")) do
    local found
    for _, f in ipairs(vim.api.nvim_get_runtime_file("parser/" .. lang .. ".so", true)) do
      if vim.startswith(f, data) then found = f end
    end
    check("treesitter parser: " .. lang, found ~= nil and pcall(vim.treesitter.language.add, lang))
  end

  -- keymaps.lua loads on VeryLazy, which a headless nvim (no UIEnter) never fires
  if not vim.g.did_very_lazy then
    vim.g.did_very_lazy = true
    vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
  end
  for _, km in ipairs({ { "i", "ii", "Exit insert mode" }, { "n", "W", "Save file" }, { "n", "Q", "Quit all" }, { "n", "Y", "Copy entire file" } }) do
    local m = vim.fn.maparg(km[2], km[1], false, true)
    check(("keymap %s %s (%s)"):format(km[1], km[2], km[3]), m.desc == km[3], m.rhs or "unmapped")
  end

  if (vim.env.THEME or "") ~= "" then
    local name = vim.g.colors_name or ""
    check("colorscheme " .. vim.env.THEME, vim.startswith(name, vim.env.THEME), "active: " .. name)
  end

  -- Markdown
  check("render-markdown.nvim loaded", package.loaded["render-markdown"] ~= nil)
  local ok_state, state = pcall(require, "render-markdown.state")
  local cfg = ok_state and state.get(buf) or nil
  if not cfg then
    check("render-markdown config", false, "render-markdown.state unavailable")
  else
    check("heading.sign = true", cfg.heading.sign == true, tostring(cfg.heading.sign))
    check("heading.icons set", type(cfg.heading.icons) == "table" and #cfg.heading.icons > 0, vim.inspect(cfg.heading.icons))
    check("checkbox.enabled = true", cfg.checkbox.enabled == true, tostring(cfg.checkbox.enabled))
    check("code.sign = true", cfg.code.sign == true, tostring(cfg.code.sign))
    check("code.width = full", cfg.code.width == "full", tostring(cfg.code.width))
  end

  -- Collect render-markdown's extmarks per row (0-based)
  local ns = vim.api.nvim_create_namespace("render-markdown.nvim")
  local function marks() return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) end
  vim.wait(10000, function() return #marks() > 0 end, 100)
  local rows = {}
  for _, m in ipairs(marks()) do
    local r = rows[m[2]] or { sign = "", virt = "" }
    rows[m[2]] = r
    r.sign = r.sign .. (m[4].sign_text or "")
    for _, chunk in ipairs(m[4].virt_text or {}) do r.virt = r.virt .. chunk[1] end
  end
  local function row(n) return rows[n] or { sign = "", virt = "" } end
  check("markdown buffer rendered", #marks() > 0, #marks() .. " extmarks")

  if cfg then
    local h1 = cfg.heading.icons[1] or ""
    check("heading icon rendered", h1 ~= "" and row(2).virt:find(h1, 1, true) ~= nil, "row 3 virt: " .. row(2).virt)
    check("heading sign rendered", vim.trim(row(2).sign) ~= "" and vim.trim(row(4).sign) ~= "", "signs: '" .. row(2).sign .. "' '" .. row(4).sign .. "'")
    check("unchecked checkbox rendered", row(6).virt:find(cfg.checkbox.unchecked.icon, 1, true) ~= nil, "row 7 virt: " .. row(6).virt)
    check("checked checkbox rendered", row(7).virt:find(cfg.checkbox.checked.icon, 1, true) ~= nil, "row 8 virt: " .. row(7).virt)
    check("code block sign rendered", vim.trim(row(9).sign) ~= "", "sign: '" .. row(9).sign .. "'")
  end

  check("marksman LSP attached (markdown)", wait_lsp(buf, "marksman", 15000))
  check(":MarkdownPreviewToggle available", vim.fn.exists(":MarkdownPreviewToggle") == 2)
  check("markdown-preview binary present", vim.fn.glob(data .. "/lazy/markdown-preview.nvim/app/bin/markdown-preview-*") ~= "")

  -- C/C++ and JSON
  vim.cmd.edit(vim.fn.fnameescape(vim.env.SAMPLE_DIR .. "/sample.cpp"))
  check("clangd LSP attached (cpp)", wait_lsp(0, "clangd", 20000))
  vim.cmd.edit(vim.fn.fnameescape(vim.env.SAMPLE_DIR .. "/package.json"))
  check("jsonls LSP attached (json)", wait_lsp(0, "jsonls", 20000))

  for _, bin in ipairs({ "tree-sitter", "marksman", "markdownlint-cli2", "markdown-toc", "clangd", "vscode-json-language-server" }) do
    check("mason bin: " .. bin, vim.fn.executable(data .. "/mason/bin/" .. bin) == 1)
  end

  out:close()
  vim.cmd("qa!")
end

-- Run once startup (and lazy-loading) has settled
vim.defer_fn(function()
  local ok, err = pcall(run)
  if not ok then
    check("verification script", false, tostring(err))
    out:close()
    vim.cmd("cq!")
  end
end, 500)
EOF

(cd "$WORK/sample" &&
  EXTRAS="${EXTRAS[*]}" TS_PARSERS="${TS_PARSERS[*]}" THEME="$THEME" SAMPLE_DIR="$WORK/sample" VERIFY_OUT="$WORK/verify.out" \
    nvim_headless "$SAMPLE" "+luafile $WORK/verify.lua") || true
grep -q 'extra: ' "$WORK/verify.out" || die "Neovim verification did not run:"$'\n'"$(log_tail)"

pass=0 fail=0 warns=0
while IFS=$'\t' read -r status name detail; do
  case "$status" in
    PASS) ((++pass)); echo "  ${C_OK}PASS${C_OFF} $name" ;;
    WARN) ((++warns)); echo "  ${C_WARN}WARN${C_OFF} $name${detail:+  ($detail)}" ;;
    *) ((++fail)); echo "  ${C_FAIL}FAIL${C_OFF} $name${detail:+  ($detail)}" ;;
  esac
done <"$WORK/verify.out"

echo
case ":$ORIG_PATH:" in
  *":$LOCAL_BIN:"*) ;;
  *) compgen -G "$LOCAL_BIN/*" >/dev/null &&
    warn "$LOCAL_BIN is not in your PATH; add to your shell rc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
if ((fail == 0)); then
  echo "${C_OK}All $pass checks passed${C_OFF}$( ((warns)) && echo " ($warns warnings)")."
  echo "Try: <Space><Space> find files, <Space>e file tree, <Space>um toggle Markdown rendering, <Space>cp browser preview."
else
  echo "${C_FAIL}$fail check(s) failed${C_OFF}, $pass passed, $warns warnings."
  echo "Last lines of the nvim log:"
  log_tail
  exit 1
fi
