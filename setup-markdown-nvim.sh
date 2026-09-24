#!/usr/bin/env bash
# Set up Markdown support in a LazyVim config, then verify it headlessly:
#   - enable the lazyvim.plugins.extras.lang.markdown extra
#     (render-markdown.nvim, markdown-preview.nvim, marksman, markdownlint-cli2, markdown-toc)
#   - override render-markdown: heading icons + signs, checkbox rendering, full-width code blocks with signs
#
# Usage:
#   ./setup-markdown-nvim.sh           install + verify
#   ./setup-markdown-nvim.sh --check   verify only (the script changes nothing; LazyVim itself may
#                                      still auto-install missing plugins when nvim starts)
set -euo pipefail

EXTRA="lazyvim.plugins.extras.lang.markdown"
MASON_PKGS=(tree-sitter-cli marksman markdownlint-cli2 markdown-toc)

CHECK_ONLY=0
case "${1:-}" in
  --check) CHECK_ONLY=1 ;;
  "") ;;
  -h | --help) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

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

# Run headless nvim with the user's config, logging its noisy output.
nvim_headless() { nvim --headless "$@" >>"$LOG" 2>&1; }

# ---------------------------------------------------------------- preflight
command -v nvim >/dev/null || die "nvim not found in PATH"
[[ $(nvim --headless --clean +'lua io.write(vim.fn.has("nvim-0.11.2"))' +qa 2>&1) == 1 ]] ||
  die "LazyVim needs Neovim >= 0.11.2 (found: $(nvim --version | head -1))"

CONFIG_DIR=$(nvim --headless --clean +'lua io.write(vim.fn.stdpath("config"))' +qa 2>&1)
DATA_DIR=$(nvim --headless --clean +'lua io.write(vim.fn.stdpath("data"))' +qa 2>&1)
LAZYVIM_JSON="$CONFIG_DIR/lazyvim.json"
OVERRIDE="$CONFIG_DIR/lua/plugins/render-markdown.lua"

[[ -f "$LAZYVIM_JSON" ]] || die "$LAZYVIM_JSON not found - is $CONFIG_DIR a LazyVim config?"
info "Neovim config: $CONFIG_DIR"

if ((!CHECK_ONLY)); then
  for cmd in git curl; do
    command -v "$cmd" >/dev/null || die "$cmd is required"
  done
  command -v npm >/dev/null || warn "npm not found: Mason cannot install markdownlint-cli2 / markdown-toc"
  command -v cc >/dev/null || warn "no C compiler (cc) found: treesitter parsers cannot be compiled"
fi

# ---------------------------------------------------------------- install
if ((!CHECK_ONLY)); then
  STAMP=$(date +%Y%m%d%H%M%S)

  # 1. Enable the lang.markdown extra in lazyvim.json
  if grep -q "\"$EXTRA\"" "$LAZYVIM_JSON"; then
    info "Extra already enabled: $EXTRA"
  else
    cp "$LAZYVIM_JSON" "$LAZYVIM_JSON.bak.$STAMP"
    if command -v python3 >/dev/null; then
      python3 - "$LAZYVIM_JSON" "$EXTRA" <<'EOF'
import json, sys
path, extra = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data.setdefault("extras", []).append(extra)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
EOF
    else
      nvim --headless --clean -l /dev/stdin "$LAZYVIM_JSON" "$EXTRA" <<'EOF'
local path, extra = arg[1], arg[2]
local data = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
data.extras = data.extras or {}
table.insert(data.extras, extra)
vim.fn.writefile({ vim.json.encode(data) }, path)
EOF
    fi
    info "Enabled extra $EXTRA (backup: $LAZYVIM_JSON.bak.$STAMP)"
  fi

  # 2. Write the render-markdown override
  mkdir -p "$(dirname "$OVERRIDE")"
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
  if [[ -f "$OVERRIDE" ]] && cmp -s "$OVERRIDE" "$WORK/render-markdown.lua"; then
    info "Override already up to date: $OVERRIDE"
  else
    [[ -f "$OVERRIDE" ]] && cp "$OVERRIDE" "$OVERRIDE.bak.$STAMP" && info "Backed up existing override to $OVERRIDE.bak.$STAMP"
    cp "$WORK/render-markdown.lua" "$OVERRIDE"
    info "Wrote $OVERRIDE"
  fi

  # 3. Install plugins
  info "Installing plugins with lazy.nvim (may take a while on a fresh machine)..."
  nvim_headless "+Lazy! install" +qa || die "lazy.nvim install failed, see log below"$'\n'"$(tail -20 "$LOG")"

  # 4. Mason tools (tree-sitter-cli is needed to build parsers on nvim-treesitter main)
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
  [[ -f "$WORK/mason.out" ]] || die "Mason step did not run, see log below"$'\n'"$(tail -20 "$LOG")"
  while IFS=$'\t' read -r status name detail; do
    if [[ $status == OK ]]; then info "  $name: $detail"; else warn "  $name: $detail"; fi
  done <"$WORK/mason.out"

  # 5. Treesitter parsers
  info "Installing treesitter parsers: markdown, markdown_inline"
  cat >"$WORK/ts.lua" <<'EOF'
require("lazy").load({ plugins = { "mason.nvim", "nvim-treesitter" } })
local ts = require("nvim-treesitter")
if type(ts.install) == "function" then
  -- nvim-treesitter main branch: async install, wait for it
  local task = ts.install({ "markdown", "markdown_inline" })
  if task and task.wait then task:wait(300000) end
else
  vim.cmd("TSInstallSync markdown markdown_inline") -- master branch
end
vim.cmd("qa!")
EOF
  nvim_headless "+luafile $WORK/ts.lua" || warn "parser install reported an error (checked again below)"

  # 6. markdown-preview.nvim prebuilt binary. Its lazy build step downloads it
  #    asynchronously, which a headless nvim exits before finishing.
  MKDP_APP="$DATA_DIR/lazy/markdown-preview.nvim/app"
  if compgen -G "$MKDP_APP/bin/markdown-preview-*" >/dev/null; then
    info "markdown-preview binary already present"
  elif [[ -f "$MKDP_APP/install.sh" ]]; then
    info "Downloading markdown-preview binary..."
    (cd "$MKDP_APP" && bash install.sh) >>"$LOG" 2>&1 || warn "markdown-preview install.sh failed"
  else
    warn "markdown-preview.nvim not installed, skipping binary download"
  fi
fi

# ---------------------------------------------------------------- verify
info "Verifying..."
[[ -f "$OVERRIDE" ]] || warn "override file missing: $OVERRIDE (render-markdown will use LazyVim defaults)"

SAMPLE="$WORK/sample.md"
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

cat >"$WORK/verify.lua" <<'EOF'
local out = assert(io.open(vim.env.VERIFY_OUT, "w"))
local function check(name, ok, detail)
  out:write((ok and "PASS" or "FAIL") .. "\t" .. name .. "\t" .. (detail or "") .. "\n")
end

local function run()
  local buf = vim.api.nvim_get_current_buf()
  local data = vim.fn.stdpath("data")

  local lazyvim = vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("config") .. "/lazyvim.json"), "\n"))
  check("lang.markdown extra enabled", vim.tbl_contains(lazyvim.extras or {}, vim.env.EXTRA))

  for _, lang in ipairs({ "markdown", "markdown_inline" }) do
    local ok = pcall(function()
      vim.treesitter.language.add(lang)
      return vim.treesitter.language.inspect(lang)
    end)
    check("treesitter parser: " .. lang, ok)
  end

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
  check("buffer rendered", #marks() > 0, #marks() .. " extmarks")

  if cfg then
    local h1 = cfg.heading.icons[1] or ""
    check("heading icon rendered", h1 ~= "" and row(2).virt:find(h1, 1, true) ~= nil, "row 3 virt: " .. row(2).virt)
    check("heading sign rendered", vim.trim(row(2).sign) ~= "" and vim.trim(row(4).sign) ~= "", "signs: '" .. row(2).sign .. "' '" .. row(4).sign .. "'")
    check("unchecked checkbox rendered", row(6).virt:find(cfg.checkbox.unchecked.icon, 1, true) ~= nil, "row 7 virt: " .. row(6).virt)
    check("checked checkbox rendered", row(7).virt:find(cfg.checkbox.checked.icon, 1, true) ~= nil, "row 8 virt: " .. row(7).virt)
    check("code block sign rendered", vim.trim(row(9).sign) ~= "", "sign: '" .. row(9).sign .. "'")
  end

  local attached = vim.wait(15000, function()
    return #vim.lsp.get_clients({ bufnr = buf, name = "marksman" }) > 0
  end, 200)
  check("marksman LSP attached", attached)

  check(":MarkdownPreviewToggle available", vim.fn.exists(":MarkdownPreviewToggle") == 2)
  check("markdown-preview binary present", vim.fn.glob(data .. "/lazy/markdown-preview.nvim/app/bin/markdown-preview-*") ~= "")

  for _, bin in ipairs({ "marksman", "markdownlint-cli2", "markdown-toc" }) do
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

EXTRA="$EXTRA" VERIFY_OUT="$WORK/verify.out" nvim_headless "$SAMPLE" "+luafile $WORK/verify.lua" || true
[[ -s "$WORK/verify.out" ]] || die "verification did not run, see log below"$'\n'"$(tail -20 "$LOG")"

pass=0 fail=0
while IFS=$'\t' read -r status name detail; do
  if [[ $status == PASS ]]; then
    ((pass++)) || true
    echo "  ${C_OK}PASS${C_OFF} $name"
  else
    ((fail++)) || true
    echo "  ${C_FAIL}FAIL${C_OFF} $name${detail:+  ($detail)}"
  fi
done <"$WORK/verify.out"

echo
if ((fail == 0)); then
  echo "${C_OK}All $pass checks passed.${C_OFF} Open a .md file: <Space>um toggles rendering, <Space>cp opens browser preview."
else
  echo "${C_FAIL}$fail check(s) failed${C_OFF}, $pass passed."
  echo "Last lines of the nvim log:"
  tail -20 "$LOG" | tr '\r' '\n' | grep -v '^\s*$' | tail -10
  exit 1
fi
