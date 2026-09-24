# nvim-all-in-one

一键安装 Neovim + [LazyVim](https://www.lazyvim.org/) 常用开发环境，并在无界面（headless）Neovim 中自动验证是否生效。

内容来自 tonngw/macman 的[《快速配置 Neovim、LazyVim 以及常用开发环境》](https://github.com/tonngw/macman/blob/main/docs/08.%20%E5%BF%AB%E9%80%9F%E9%85%8D%E7%BD%AE%20Neovim%E3%80%81LazyVim%20%E4%BB%A5%E5%8F%8A%E5%B8%B8%E7%94%A8%E5%BC%80%E5%8F%91%E7%8E%AF%E5%A2%83%EF%BC%8C%E5%A6%82%E6%9E%9C%E4%B9%8B%E5%89%8D%E6%9C%89%E4%BA%BA%E8%BF%99%E4%B9%88%E5%86%99%E5%B0%B1%E5%A5%BD%E4%BA%86.md)，再合并本仓库原有的 Markdown 配置（render-markdown 覆盖项）。

## 使用

```bash
./install.sh                     # 安装 + 验证
./install.sh --theme catppuccin  # 同时设置主题：gruvbox | everforest | catppuccin | tokyonight
./install.sh --no-deps           # 不装系统包，只配置 Neovim
./install.sh --check             # 只验证
./install.sh --help
```

脚本可重复运行，已完成的步骤会跳过。在 Ubuntu 26.04 和 Arch Linux 的全新容器中验证过（root 用户和带 sudo 的普通用户都测过）。脚本也支持 Fedora（dnf）和 macOS（Homebrew），但这两种没测过。

## 会安装 / 配置什么

### 1. 系统依赖（文章第 2、3.1、3.3 节）

| 依赖 | 用途 |
| --- | --- |
| Neovim >= 0.11.2 | Arch / macOS 用包管理器装；Ubuntu / Debian / Fedora 下载官方 release 到 `~/.local/opt`，并链接到 `~/.local/bin/nvim`（Ubuntu 仓库里的版本通常太旧） |
| git、curl、wget、unzip、xz | 插件、Mason 下载与解压 |
| C 编译器（build-essential / gcc） | 编译 treesitter 解析器 |
| ripgrep、fd | 文件与内容搜索（Debian 系的 `fdfind` 会链接成 `~/.local/bin/fd`） |
| lazygit | 仓库里没有时从 GitHub release 下载 |
| luarocks、node、npm，以及 `npm install -g neovim` | 修复 `:LazyHealth` 报的问题，Mason 装 npm 包也需要 node |
| Nerd Font | 没有时安装 JetBrainsMono Nerd Font（macOS 用 brew cask，Arch 用 `ttf-jetbrains-mono-nerd`，其余下载到 `~/.local/share/fonts`）。没有 fontconfig 的服务器 / 容器会跳过，字体要装在运行终端的那台机器上 |

只安装缺少的命令。需要 root 权限的步骤用 `sudo`。Arch 上执行 `pacman -Syu --needed`（Arch 不支持部分升级）。

### 2. LazyVim starter（文章 3.2 节）

如果配置目录已经是 LazyVim 配置，就**在原配置上合并**，不会覆盖。否则先把旧的 config / data / state / cache 目录改名为 `*.bak.<时间戳>`，再克隆 `LazyVim/starter` 并删除它的 `.git`。

### 3. Neovim 配置

| 项目 | 位置 | 来源 |
| --- | --- | --- |
| Extras：`lang.clangd`、`lang.json`、`lang.markdown` | `lazyvim.json`（通过 LazyVim 自己的写入函数启用，效果同 `:LazyExtras`） | 文章 4.5、4.6 节 |
| 快捷键 | `lua/config/keymaps.lua` 末尾的标记块 | 文章 4.3 节 |
| render-markdown 覆盖：标题图标 + sign、checkbox、全宽代码块 + sign | `lua/plugins/render-markdown.lua` | 本仓库原脚本 |
| 主题（仅 `--theme`） | `lua/plugins/colorscheme.lua` | 文章 4.4 节 |

快捷键：

| 模式 | 按键 | 作用 |
| --- | --- | --- |
| 插入 | `ii` | 退出到普通模式 |
| 普通 | `W` | 保存（会覆盖原生的 `W` 按 WORD 跳转） |
| 普通 | `Q` | 全部退出 |
| 普通 | `Y` | 复制整个文件（原生是复制到行尾） |

快捷键写在 `-- >>> install.sh keymaps` 和 `-- <<< install.sh keymaps` 之间，重跑时只替换这一块。块外面的内容不会被改动。

默认不改主题，因为不少配置在别处管理主题（例如 Omarchy 的 `lua/plugins/theme.lua`）。

### 4. 插件与工具

- lazy.nvim 安装插件（启用 extras 前后各跑一次）
- Mason：`tree-sitter-cli`、`marksman`、`markdownlint-cli2`、`markdown-toc`、`clangd`、`json-lsp`
- treesitter 解析器：`markdown`、`markdown_inline`、`c`、`cpp`、`json`、`json5`
- markdown-preview 预编译程序（lazy 的 build 步骤是异步的，headless 模式下来不及完成，所以单独下载）

### 备份

修改前会备份，后缀为 `.bak.<时间戳>`：`lazyvim.json`、`keymaps.lua`、`render-markdown.lua`、`colorscheme.lua`。只有内容确实变化时才备份，刚克隆的 starter 不备份。

## 验证内容

脚本用 headless Neovim 依次打开示例 `.md`、`.cpp`、`.json` 文件，逐项输出 `PASS` / `WARN` / `FAIL`：

- 必需命令：git、curl、unzip、cc、rg、fd、node、npm（缺少记为 FAIL）
- 可选项：wget、lazygit、luarocks、Nerd Font（缺少记为 WARN）
- 三个 extras 已启用
- 六个 treesitter 解析器由 nvim-treesitter 安装（Neovim 自带的 c / markdown 解析器不算）
- 四个快捷键已映射
- 主题已生效（仅 `--theme`）
- render-markdown 的覆盖选项已生效，标题图标、标题 sign、两种 checkbox、代码块 sign 确实渲染出来了
- marksman、clangd、jsonls 三个 LSP 都已连接
- `:MarkdownPreviewToggle` 命令和预编译程序存在
- 六个 Mason 工具可执行

没有 FAIL 时退出码为 `0`；有 FAIL 时退出码为 `1`，并打印 Neovim 日志末尾。

> `--check` 模式下脚本本身不改任何文件，但如果插件缺失，LazyVim 启动时仍可能自动安装它们。
>
> 浏览器预览需要图形界面，headless 下测不了，脚本只检查命令和程序是否就绪。

## 在配置副本上试用

配置目录通过 `stdpath("config")` 获取，支持 `NVIM_APPNAME` 和 `XDG_CONFIG_HOME`：

```bash
cp -r ~/.config/nvim ~/.config/nvim-test
NVIM_APPNAME=nvim-test ./install.sh --no-deps
```

插件和工具会装到 `~/.local/share/nvim-test`。试完后删除 `~/.config/nvim-test` 和 `~/.local/{share,state}/nvim-test`、`~/.cache/nvim-test` 即可。

## 装好之后

如果脚本提示 `~/.local/bin` 不在 PATH 里，在 shell 配置中加上 `export PATH="$HOME/.local/bin:$PATH"`，并把终端字体设为 Nerd Font。

| 快捷键（`<leader>` 为空格） | 作用 |
| --- | --- |
| `<Space><Space>` | 搜索文件 |
| `<Space>e` | 打开 / 关闭目录树 |
| `Shift+h` / `Shift+l` | 左右切换 buffer |
| `Ctrl+h/j/k/l` | 在窗口间移动 |
| `<Space>um` | 开关 Markdown 渲染 |
| `<Space>cp` | Markdown 浏览器预览（`:MarkdownPreviewToggle`） |

通过 SSH 使用时浏览器不会自动打开：执行 `:MarkdownPreviewToggle` 后用 `:messages` 查看预览地址，并做好端口转发。

修改 render-markdown 样式：编辑 `lua/plugins/render-markdown.lua` 中的 `opts`。注意重跑脚本时会备份你的版本并写回内置配置，要保留修改请同步改脚本里对应的 heredoc，或只用 `--check`。

## 卸载

1. 在 `:LazyExtras` 中取消 clangd / json / markdown（或从 `lazyvim.json` 的 `extras` 中删除）
2. 删除 `lua/plugins/render-markdown.lua`、`lua/plugins/colorscheme.lua`，以及 `keymaps.lua` 中的标记块
3. 在 Neovim 中执行 `:Lazy clean`；Mason 工具可在 `:Mason` 中卸载
4. 通过 release 下载安装的程序在 `~/.local/opt/nvim-linux-*`、`~/.local/bin/{nvim,fd,lazygit}`
