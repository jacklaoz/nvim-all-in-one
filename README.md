# setup-markdown-nvim

一键给 [LazyVim](https://www.lazyvim.org/) 配置 Markdown 支持，并在无界面（headless）Neovim 中自动验证是否生效。适合在新机器上快速安装，或确认已有机器的配置是否完整。

## 会安装 / 配置什么

| 组件 | 作用 |
| --- | --- |
| LazyVim extra `lang.markdown` | 启用下面的插件和工具 |
| [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) | 在 buffer 内渲染 Markdown |
| [markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim) | 浏览器实时预览 |
| marksman | Markdown LSP（Mason 安装） |
| markdownlint-cli2、markdown-toc | lint 与目录生成（Mason 安装） |
| treesitter 解析器 `markdown`、`markdown_inline` | 渲染依赖 |

在 LazyVim 默认设置之上，脚本写入 `lua/plugins/render-markdown.lua` 覆盖以下选项：

- 标题：显示图标（`󰲡 󰲣 󰲥 …`）和左侧 sign
- checkbox：渲染 `[ ]` / `[x]`
- 代码块：背景全宽，左侧显示语言图标 sign

## 前置条件

- Neovim **>= 0.11.2**
- 已有 LazyVim 配置（配置目录下存在 `lazyvim.json`）
- `git`、`curl`（必需）
- `npm`（Mason 安装 markdownlint-cli2 / markdown-toc 需要）
- C 编译器 `cc`（编译 treesitter 解析器需要）
- 终端使用 [Nerd Font](https://www.nerdfonts.com/)，否则图标会显示为方框

缺少 `npm` 或 `cc` 时脚本只给出警告，相关检查项会在验证阶段失败。

## 使用

```bash
chmod +x setup-markdown-nvim.sh

./setup-markdown-nvim.sh           # 安装 + 验证
./setup-markdown-nvim.sh --check   # 只验证
./setup-markdown-nvim.sh --help    # 查看用法
```

新机器上首次安装大约需要一分钟（取决于网络）。脚本可重复运行，已完成的步骤会跳过。

配置目录通过 `nvim` 的 `stdpath("config")` 获取，因此支持 `NVIM_APPNAME` 和 `XDG_CONFIG_HOME` 等环境变量。例如先在一份配置副本上试用，不影响正在用的配置：

```bash
cp -r ~/.config/nvim ~/.config/nvim-test
NVIM_APPNAME=nvim-test ./setup-markdown-nvim.sh
```

插件和工具会装到 `~/.local/share/nvim-test`，试完删除这两个目录即可。

## 安装步骤

1. 检查 Neovim 版本、LazyVim 配置和依赖命令
2. 在 `lazyvim.json` 中启用 `lazyvim.plugins.extras.lang.markdown`
3. 写入 `lua/plugins/render-markdown.lua`
4. 用 lazy.nvim 安装插件
5. 用 Mason 安装 `tree-sitter-cli`、`marksman`、`markdownlint-cli2`、`markdown-toc`
6. 安装 treesitter 解析器 `markdown`、`markdown_inline`
7. 下载 markdown-preview 的预编译程序（lazy 的 build 步骤是异步的，headless 下来不及完成，所以单独处理）

### 备份

修改前会备份原文件，后缀为时间戳：

- `lazyvim.json.bak.<时间戳>`
- `lua/plugins/render-markdown.lua.bak.<时间戳>`（仅当已有文件且内容不同时）

## 验证内容

脚本用 headless Neovim 打开一个示例 Markdown 文件，逐项输出 `PASS` / `FAIL`：

- `lang.markdown` extra 已启用
- treesitter 解析器可用
- render-markdown 已加载，且上面的覆盖选项已生效
- 标题图标、标题 sign、两种 checkbox、代码块 sign 确实渲染出来了
- marksman LSP 已连接
- `:MarkdownPreviewToggle` 命令和预编译程序存在
- Mason 的三个工具可执行

全部通过时退出码为 `0`，否则为 `1` 并打印 Neovim 日志末尾，便于排查。

> `--check` 模式下脚本本身不改任何文件，但如果插件缺失，LazyVim 启动时仍可能自动安装它们。
>
> 浏览器预览需要图形界面，无法在 headless 下测试，脚本只检查命令和程序是否就绪。

## 装好之后怎么用

打开任意 `.md` 文件即自动渲染；光标所在行显示原始 Markdown，方便编辑。

| 快捷键（`<leader>` 为空格） | 命令 | 作用 |
| --- | --- | --- |
| `<Space>um` | — | 开关 buffer 内渲染 |
| `<Space>cp` | `:MarkdownPreviewToggle` | 打开 / 关闭浏览器预览 |

通过 SSH 使用时浏览器不会自动打开：执行 `:MarkdownPreviewToggle` 后用 `:messages` 查看预览地址，并做好端口转发。

## 修改渲染样式

编辑 `~/.config/nvim/lua/plugins/render-markdown.lua` 中的 `opts`，LazyVim 会把它合并到 extra 的默认配置上。可用选项见 render-markdown.nvim 的 README。

如果改了这个文件又重新运行脚本，脚本会备份你的版本并写回脚本内置的配置。要保留自己的修改，请同步改脚本里对应的 heredoc，或只用 `--check`。

## 卸载

1. 从 `lazyvim.json` 的 `extras` 中删除 `lazyvim.plugins.extras.lang.markdown`（或在 `:LazyExtras` 中取消）
2. 删除 `lua/plugins/render-markdown.lua`
3. 在 Neovim 中执行 `:Lazy clean`；Mason 工具可在 `:Mason` 中卸载
