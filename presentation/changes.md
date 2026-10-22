# 变更记录

## 2026-10-22

### 第一版：在 Tuna 里用 Cardinal 搜全盘文件

- **入口**：在 Tuna 里输入 "file"（或 "find"、"cardinal"），选中 "Search Files" 这一项后按 → 进入。进入后，接下来输入的内容都交给 Cardinal 搜索。
  - 入口叫 "Search Files" 而不是 "Cardinal"：用户想的是"找文件"这件事，不会去想背后用的是哪个应用。
  - Tuna 会记住你的选择，用过几次以后，输入 "f" 就能选中它。
  - Tuna 的插件接口不支持把搜索结果直接混进主搜索框，所以必须先进入这个入口再搜。
- **名字记得不完全准也能找到**：Cardinal 只做连续字符匹配，搜 `change.md` 找不到 `changes.md`。现在搜不到时，会自动把关键词按标点拆成几个词再搜一次（`change.md` 拆成 `change` 和 `md`，要求名字里两个词都有）。用了 Cardinal 语法的搜索不会拆。
- **边打字边出结果**：停止输入约 0.12 秒后就会发起搜索。Cardinal 一般在 0.1 秒内返回，只输入一个字母时约 0.3 秒。
- **每条结果**
  - 文件名，下面一行是所在文件夹和修改时间，例如 "~/Documents · 2 days ago"。
  - 显示 Tuna 自带的文件图标和预览。
  - 回车直接打开文件。按 Tab 进入动作栏，可以用 Tuna 对文件的所有操作（在访达中显示、Quick Look、移动等）。
  - ".app" 这类应用程序包当作一个整体，不会被当成可以点进去浏览的文件夹。
- **排序**：直接沿用 Cardinal 给的顺序，即个人文件优先，系统、应用内部、缓存、编译生成的文件排在最后。
- **条数**：最多显示 50 条。Cardinal 找到更多时，最后一条是 "Show all 12,345 results in Cardinal"，选中后会打开 Cardinal 窗口，并填好同样的关键词。全部结果都已显示时，不出现这一条。
- **各种状态的提示**
  - 刚进入、还没输入时："Search every file on this Mac"，并提示可以用 Cardinal 的搜索语法。
  - Cardinal 没在运行：只显示一条 "Open Cardinal"，选中后会在后台启动 Cardinal，Tuna 窗口保持打开，可以接着搜。
  - Cardinal 第一次扫描全盘还没完成："Cardinal is indexing this Mac"，并显示已扫描的文件数。
  - 没搜到："No files found"。
  - 搜索语法写错："Check the search syntax"，并显示 Cardinal 给出的具体错误。
  - Cardinal 正忙："Cardinal is busy"。
- **不需要任何设置**：插件会自动读取 Cardinal 每次启动时生成的访问钥匙。
- **需要的 Cardinal 版本**：必须是我们 fork 里带查询接口的版本，官方版本没有这个接口。
