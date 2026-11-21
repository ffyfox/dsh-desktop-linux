# 补丁

按文件名顺序应用（见 `scripts/apply-patches.sh`），全部相对上游 `9c2670d3`（tag `dsh-v0.2.2-rc.5`）。

组织约定：**一条改动只属于一个补丁**。每个补丁都是相对同一个基线的独立 diff，改动互不重复、
按编号应用（顺序依赖见下）。补丁由 `git diff -- <files>` 从开发工作树生成；**一个文件可以被
多个补丁触及**，此时必须按「基线 + 只有这一个补丁」的隔离树取 diff，否则会把另一个补丁的
hunk 一起带进来。

**`0017`、`0018` 与 `0019` 是这条约定的三个已知例外。**

`0017` 的 5 个文件（`src/node-environment.ts`、`src/main.ts`、`tests/host-process.spec.ts`、
`tests/node-environment.spec.ts`、`desktop-host/src/index.ts`）全部也属于 `0008`，而且它的 diff 上下文含
`0008` 新增的行（`resourcesPath?: string` 紧挨着 `0008` 加的 `readonly electron: boolean`），所以它单独
打在干净基线上会直接 reject，只有排在 `0008` 之后才成立 —— 现有系列靠「按文件名顺序」恰好满足。
重生这类补丁要走两阶段：先在「新基线 + 前置补丁」上重算，再叠它自己的增量。

`0018` 同理：18 个文件里 4 个（`src/main.ts`、`src/preload-windows.ts`、`tests/main-startup.spec.ts`、
`tests/preload-windows.client.spec.ts`）已属于 `0008` / `0016`，而 `preload-windows.ts` 的 hunk 正落在
`0016` 放宽平台门的那几行上，所以它也只有排在 `0016` 之后才成立；另外 14 个是本系列第一次触及
（`src/glass-mode.ts`、`src/glass-document.ts`、`src/web-document.ts`、`tests/glass-mode.spec.ts`、
`tests/glass-document.spec.ts`、`tests/web-document.spec.ts`，以及 `packages/client/ui-layout` 的
`AppFrame.tsx` / `AppFrame.module.css` / `tests/app-frame.client.spec.tsx`、`packages/client/ui-sidebar`
的 `SidebarRoot.tsx` / `SidebarRoot.module.css` / `tests/sidebar-root.client.spec.tsx`，以及 `ui-plugin-manager` / `ui-schedule` 的两个页面样式表
`src/client/PluginManagerPage.module.css` / `src/client/TaskManagerPage.module.css`），
其中 4 个是新增文件。`0019` 共用 `src/main.ts`、`src/preload-windows.ts`、`src/welcome-window.ts`、`tests/main-startup.spec.ts`、
`tests/preload-windows.client.spec.ts`、`tests/welcome-window.spec.ts` 与 `packages/client/ui-sidebar/src/client/SidebarRoot.module.css`，同样依赖于前序补丁落位；因此 `apply-patches.sh --check` 对干净树只会让
`0001`–`0016` 逐个通过，全套验证需走顺序 `git apply` 与 `patch -Np1`。

已验证（0.2.2-rc.5）：本版为轻量同步（相对 `rc.4` 共 5 笔提交：DeepSeek 模型默认使用服务端搜索及搜索设置文档/测试更新、LiveShare `owner-credential-horizon` 测试改用真实时钟、以及版本号升至 `0.2.2-rc.5`）；
16 个补丁与 `rc.4` 逐字节一致，仅 `0006` 因 `apps/desktop/package.json` 第 3 行版本号上下文刷新
`index` 哈希。17 个补丁按序打在完整的上游 release 源码包（tag `dsh-v0.2.2-rc.5`）上，`patch -Np1`
（makepkg 的 `prepare()`）与 `git apply`（`apply-patches.sh` / CI）均干净通过，89 个触及文件
（含 `tray-linux.png`）两条路线逐字节一致；`makepkg --verifysource` 校验 19 项 source 全部通过。
`build.sh --all` 一次出齐三格式：AppImage `372,138,560` B（sha256 `fec6d46a…`）、deb `293,716,212` B
（`8d95885a…`）、rpm `246,988,049` B（`4c058215…`），`smoke:prepared-runtime` 与
`smoke:packaged-runtime` 均通过。`verify.sh --runtime` **49 通过 / 0 失败 / 7 跳过**（6 个为旧版
`rc.3`/`rc.4` 产物跳过、1 个为 `3080` 未监听）：Host 跑在 `primary-runtime` 独立 Node 上且收到
`DSH_DESKTOP_RESOURCES_PATH`（`0017`），`data-windows-titlebar` 与 `[data-windows-menu]` 在场
（`0016`），2 个渲染进程均在独立 user namespace 且 seccomp 生效，StatusNotifierItem 托盘菜单可读，
共享根隔离且真实 `~/.dsh` 未被触碰。产物内 `resources/runtime/cli` 不存在、`dsh/package.json` 版本
`0.2.2-rc.5`、`resources/app/package.json` 的 `dshBuildCommit` 记 `9c2670d3…`（`dshBuildDirty: true`）。
去代理下上游桌面单测（`apps/desktop/tests` + `apps/desktop-host/tests`）`194` 文件 `2348` 通过 / `65`
跳过 / `0` 失败，补丁关联客户端包（`ui-layout`、`ui-sidebar`、`ui-brand-official`、`client-build-environment`）与本版变更测试（`ui-settings-web-search`、`owner-credential-horizon`）`25` 文件 `411` 用例全通过。

**编号 `0014` 已作废，空号不复用。** 它当年把 lockfile 里 electron 的解析从 44.0.0 提到 44.4.5
（那个版本的 Linux 托盘在 KDE 与 GNOME 下都注册不上）；0.2.1-alpha.2 的 lockfile 自己解析到 44.7.0，
上游的 `^44.7.0` 也已经不允许 44.4.5 —— 留着不只是多余，还会让 `pnpm install --frozen-lockfile`
直接失败。所以删掉它，`0015` / `0016` 的编号保持不动：已推送的历史（`e8a3fcd` 的标题与正文）里
点名的就是 `0015`，重编号只会让发布出去的文字与工作树对不上。

**编号 `0015` 也已作废（自 0.2.2-alpha.2 起），同样不复用。** 它原本给关窗提示浮层在 Wayland 下补一次
`did-finish-load` 的 reveal：那时浮层是独立的 `transparent: true` + `show: false` 窗口，只在
`ready-to-show` 里 `show()`，而 Wayland 下这种窗口不报首帧，浮层建好了却 `isVisible() === false`。
0.2.2-alpha.2 把浮层换成挂在主窗口上的 `WebContentsView`（`setBackgroundColor('#00000000')` +
`contentView.addChildView`），既没有窗口也没有 `show()` / `ready-to-show`，补丁对新结构是零改动，
所以整条移除。

## 让 Linux 成为受支持的 target（0001–0007）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0001-desktop-target-model-add-linux-x64.patch` | `desktop-build-paths.{mjs,d.mts}`、`desktop-auto-update-environment.{mjs,d.mts}`、`desktop-release-store.ts`、`retain-desktop-ci.ts` | target 白名单加 `linux-x64` 与 `linux-arm64`（`arm64` 折入现有补丁，文件名保留 `-x64` 历史名）；`desktopTargetPlatform` 返回 `'linux'`；新增 `desktopElectronExecutablePath()`；保留清单的 schema 认出两个 Linux target，并放宽 `retain-desktop-ci.ts` 中 `route.target` 的包含判断，避免 `tsc -p tsconfig.host.json` 报错 |
| `0002-package-target-add-linux-x64.patch` | `package-target.ts`、`desktop-upload-plan.ts` | 打包目标表加 `linux-x64` 与 `linux-arm64`；宿主守卫改为「宿主架构 == 目标架构」（交叉构建在 prepare 阶段即需执行目标平台的 Electron / Node / Python，必须原生构建） |
| `0003-electron-builder-linux-configuration.patch` | `electron-builder-config.mjs`、`electron-builder.config.d.mts`、`tests/installer-packaging.spec.ts` | Linux 关闭 asar；显式 `executableName`；Linux 不嵌入强制更新策略；Linux 的打包格式与包元数据来自发布设置（见 `0011`）；显式钉住 deb/rpm 的 `packageName` / `packageCategory` 与 `linux.synopsis`；显式列出 deb/rpm 运行依赖并去掉 Electron 既不链接也不加载的 `libxss1` / `libXScrnSaver`（指定 `depends` 会替换整个默认数组，其余默认项保留；单测改为对着 `FpmTarget.getDefaultDepends()` 核这份数组，上游新增默认项时测试会红）；用 `appImage.executableArgs: []` 去掉 legacy 工具集写死的 `--no-sandbox`；Linux 图标显式指定为 SVG —— 单个 PNG 文件会被 electron-builder **原样按自身像素尺寸**装进 `hicolor/1024x1024/apps`，而多个发行版的 `hicolor/index.theme` 并不声明该目录（Arch 就没有），图标会解析不到；SVG 落到 `hicolor/scalable/apps`，所有发行版都声明 |
| `0004-prepare-target-electron-distribution.patch` | `prepare-dsh.ts`、`prepare-runtime.ts` | Electron 分发路径按 target 推导，不再假设「非 mac 即 win32」；打包期 `pnpm install` / 运行时冒烟改用 Host 运行时；`versions.json.node` 记为 payload 实际运行的 Node 版本；Linux 上整块跳过 `prepare:cli`（见「注意」） |
| `0005-desktop-linux-release-settings.patch` | `desktop-package-environment.{mjs,d.mts}`、`desktop-toolchain-preflight.ts`、`.gitignore`、`.env.linux.example`、`tests/desktop-package-environment.spec.ts` | 支持 `.env.linux`（读取dotenv 逻辑随上游在 `desktop-file-settings.mjs`，Linux 白名单留在常量与平台分支）；Linux 不套用 Windows/macOS 专属设置；Linux 不要求策略 origin；修掉 `win32 ? … : macOS` 的隐含假设；Linux 文件白名单加 `MAINTAINER`/`HOMEPAGE`（并从环境里剥掉，保证发布设置只由文件拥有）；打了 rpm 才预检 `rpmbuild` |
| `0006-desktop-package-linux-scripts.patch` | `apps/desktop/package.json`、`scripts/client-build-environment.ts` 与其单测、`packages/client/ui-brand-official/src/client/index.ts` 与其单测 | `package:linux:{x64,arm64}` 与 `package:linux:{x64,arm64}:dir`；未签名 Linux 包的官方品牌层适配（见下） |
| `0007-tests-linux-x64-supported.patch` | 3 个 `tests/*.spec.ts` | 把「断言 Linux 抛错」改成「断言 `linux-x64` 与 `linux-arm64` 受支持」 |

`0006` 同时负责未签名 Linux 包的品牌层：`package:linux:*` 脚本一律走 `--unsigned`，上游会让未签名包改用 `build --profile local`，若不调整会使侧栏与窗口标题呈现为「本地构建」。因此 `scripts/client-build-environment.ts` 在 `local` profile 补上 `DSH_CLIENT_TITLE`（复用 `OFFICIAL_CLIENT_BUILD_ENVIRONMENT` 常量），`ui-brand-official` 的守卫从「不是 `official` 就返回」改为「**没有**选 profile 才返回」（未选 profile 的纯 web 构建仍留空）；构建记录本身仍保持 `DSH_CLIENT_BUILD_PROFILE: local`，不冒充 `official`，不影响 `pack-local-packages` 与打包记录配对校验。

## 让 Host 跑在真 Node 上（0008–0010）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0008-desktop-host-runtime-standalone-node.patch` | `src/node-environment.ts`、`src/host-process.ts`、`src/main.ts`、`desktop-host/src/{index,cli}.ts`、`scripts/node-bin/node`、6 个 spec/e2e | 引入 `DesktopNodeRuntime`；Linux 上 Host 走 primary-runtime 的真 Node（Host 入口把 `process.argv[4]` 记进 `DSH_PRIMARY_RUNTIME`，`runtimeArchivePath()` 位于 `cli.ts`）；`ELECTRON_RUN_AS_NODE` 只在真 Electron 运行时下设置；node shim 缺 `DSH_DESKTOP_NODE_EXECUTABLE` 时报错退出 78（不再静默 `exec` 空路径，那会打成 `line 6: exec: : not found` 的 exit 127）；`dsh` CLI 在「真目录树」布局下按 `resources/runtime` 找 supportDir（关掉 asar 后原来那段推导会落到 `resources/app/runtime`，见「注意」）。`desktopNodeRuntime()` 的返回值从字符串变成对象，6 个相关 spec/e2e 里 `DesktopHostProcess` 的 `node` 参数与断言同步改成 `DesktopNodeRuntime` 对象 |
| `0009-desktop-packaging-host-runtime.patch` | `scripts/dev.ts`、`scripts/smoke-{runtime,prepared-runtime,packaged-runtime}.ts`、`scripts/sign-primary-runtime.ts`、`tests/fixtures/{runtime-payload-smoke,pnpm-smoke}.mjs`、`tests/prepared-runtime-smoke.spec.ts` | 把 Host 运行时贯穿 dev / 打包 / 冒烟；按目标架构计算未打包目录（electron-builder 以 x64 为默认架构，x64 为 `linux-unpacked`，arm64 为 `linux-arm64-unpacked`）；payload smoke 的 Electron 专属断言改为按平台判断 |
| `0010-desktop-linux-policy-opt-out.patch` | `desktop-policy-environment.{mjs,d.mts}`、`tests/desktop-policy-environment.spec.ts` | 新增 `desktopPlatformEmbedsPolicy()`：策略服务只认 `desktop-win` / `desktop-mac`，Linux 不参与 |

## 产物与包元数据（0011–0012）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0011-desktop-linux-package-metadata.patch` | `desktop-linux-packages.{mjs,d.mts}`、`tests/desktop-linux-packages.spec.ts` | 新增 `resolveDesktopLinuxFormats()`（`DSH_DESKTOP_TARGET_FORMATS`，缺省只出 AppImage）与 `resolveDesktopLinuxPackageMetadata()`（deb/rpm 必须给 `Name <email>` 形式的 maintainer 和绝对 http(s) homepage，两者一起报错） |
| `0012-desktop-build-commit-release-archive.patch` | `desktop-build-commit.{mjs,d.mts}`、`tests/desktop-build-commit.spec.ts` | `readDesktopBuildCommit()` 先认环境里记下的 `DSH_DESKTOP_BUILD_COMMIT` / `_DIRTY`（打包入口读一次、再传给每个子进程，子进程跑在构建树上），没有才读 git checkout，两者都没有才报错。上游从 checkout 构建，distro 打包从 release 源码包构建，后者没有 `.git`，而它的构建树常常就落在打包仓库自己的工作树里（见「注意」） |

`0003` 消费 `0011`，`0005` 也消费 `0011`：格式选择和包元数据的**规则**只有一份（`0011`），
`0003` 拿去配 electron-builder，`0005` 拿去做打包最前面的预检。按「一条改动只属于一个补丁」，
规则本身单独成一个补丁。

## 让 Linux 也有托盘（0013）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0013-desktop-linux-tray.patch` | `src/main.ts`、`src/tray.ts`、`src/background-notice.ts`、`scripts/electron-builder-config.mjs`、`scripts/render-tray-icon.ts`、`tests/main-startup.spec.ts`（应用菜单构建断言改取最后一个首项带 `submenu` 的调用：Linux 在 `refreshApplicationMenu()` 时顺带重建托盘菜单，`lastCall` 会落在托盘菜单上） | 托盘的创建条件从只认 `win32` 放宽到 `win32 \|\| linux`；Linux 的托盘图是 `resources/tray-linux.png`（单张 PNG，托盘宿主自己缩放到面板；**用应用图标自身的留白，不做 Windows 那 20% 放大**，见「注意」）；首次关窗的一次性提示同样覆盖 Linux —— 它的文案本来就是「可在系统托盘中重新打开窗口」，在 Linux 上这句话只有有了托盘才成立；渲染器除 ICO 之外也输出那张 PNG；electron-builder 的 Linux `extraResources` 把它带进产物的 `resources/` |
托盘 PNG 是二进制，`patches/` 装不下：makepkg 用的是 GNU patch，它不支持 git 的二进制补丁。
所以这张图作为普通本地 `source` 走，仓库里存在 `assets/tray-linux.png`，由两条路径各自放进
`apps/desktop/resources/`：PKGBUILD 的 `prepare()`（`makepkg` 路线）和 `scripts/apply-patches.sh`
（CI 与本地 `build.sh` 路线）。刷新它 = 在 `apps/desktop` 里跑 `pnpm run render:tray-icon`，
再把输出的 `resources/tray-linux.png` 拷进 `assets/`（图和 Windows 托盘同源，都是
`resources/icon-windows.svg`）。

## 让 Linux 的标题栏与 Windows 一致（0016）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0016-desktop-linux-caption.patch` | `src/main.ts`、`src/preload-windows.ts`、`src/welcome-window.ts`、`tests/{main-startup,welcome-startup,welcome-window,preload-windows.client}.spec.ts` | Linux 借用 Windows 的 caption：`createWindow()` 里对 Linux 关掉原生菜单栏（`setMenuBarVisibility(false)`，application menu 仍挂着，所以菜单项与加速键都还在）；preload 的平台门从只认 `win32` 放宽到 `win32 \|\| linux`，页面因此拿到 `data-windows-titlebar` 并挂上「应用 / 编辑」两个自绘菜单按钮。这两个按钮点开的是原生弹窗，走 Windows 那条 `DESKTOP_IPC.windowsMenu`，所以那个 IPC 块与右键菜单的角色标签也一起放宽到 Linux —— 角色项（`undo` / `copy` / `selectAll` …）因此改用 DSH 字典里的标签，不再回落 Electron 内置的英文角色名。`windowsAppearance` 这个 handler 里真正碰 Electron API 的那一句（`setTitleBarOverlay`）**仍只归 Windows**：窗口的 `titleBarOverlay` 只在 `win32 && primary` 时创建，Linux 上调它必抛异常（见「注意」），所以只放宽菜单与语言同步，不放宽 overlay 上色。未登录的欢迎窗是另一条 `new BrowserWindow()` 路径（`welcome-window.ts`），那个窗口里没有页面内 caption 条，Linux 的原生菜单栏会在标题栏下面独自占一条，所以也一并关掉。测试上：Linux 分支会调 `setMenuBarVisibility()`，三处假窗口替身补上这个方法（`main-startup.spec.ts` 里那 5 个 Linux 用例原本会因此卡到 5 秒超时）；`preload-windows.client.spec.ts` 里「Linux 上不装 Windows 控件」的断言换成「Linux 装 caption 并上报取色」 |

这是**半统一**：窗口装饰一律不动（KDE 是 KWin 的装饰插件、GNOME 是 Mutter 画的、平铺窗口管理器
本来就没有装饰），只把网页内那一条 caption 对齐 Windows。Linux 的 in-page 菜单与 Windows 共用
同一套属性与度量（`data-windows-titlebar`、`--dsh-windows-titlebar-height: 40px`、
`--dsh-windows-menu-start`，见 `preload-menu.ts`），所以客户端一个字都没改。

**原生那条菜单栏也归这里。** 非 darwin 的 `platformMenus()` 原本只写 `{ role: 'editMenu' }`，
而 Electron 的 `editMenu` 角色按**它自己的语言**取标题与子项（英文），于是中文界面上就成了
「应用 / Edit」。这条菜单栏平时看不见（`setMenuBarVisibility(false)`），只有玻璃模式（`0018`）
对 Linux 打开 `setAutoHideMenuBar(true)` 之后按 Alt 才露出来 —— 一露就是中英混排。所以这一版把
caption 弹窗里那份 `editItem` / `editMenuItems` 提到 `main()` 作用域，弹窗与原生菜单共用同一个
构造器：标题取 `messages.edit`，子项（撤销 / 重做 / 剪切 / 复制 / 粘贴 / 删除 / 全选）取
`messages.*`，点击走 `shortcuts.sendEditingKey` 合成按键（编辑器自己的历史只认键盘事件，不走
Chromium 的 undo 栈）。测试上 `main-startup.spec.ts` 的平台菜单用例同步改成「非 darwin 的第二个
菜单有 label 与子项」而不是「有一个 `editMenu` 角色」。

同一处还有第二个漏项：`applicationItems()` 里退出项的 label 只给了 macOS（「退出 DeepSeek Harness」）
和 Windows（「退出」），Linux 落进空对象，于是显示 Electron 内置的英文 `Quit` —— 与旁边由 DSH 字典
提供的「关于 DeepSeek Harness」「检查更新…」「开发者工具」中英混排。非 darwin 分支统一取
`messages.exitApplication`（中文「退出」），至此原生菜单每一项都走 DSH 字典。

`0016` 启动实测（0.2.1-alpha.2 这份产物；用隔离 `DSH_HOME` + 独立 `--user-data-dir` 起，KWin 读
`frameGeometry` / `clientGeometry`，CDP 读渲染视口）：主窗口 frame 1280x848、客户区 1280x820、
视口 820；欢迎窗 frame 600x757、客户区 600x729、视口 729。两个窗口的「客户区 − 视口」都是 0，
即都没有原生菜单栏（`frame − client` 的 28px 是 KWin 画的装饰），主窗口页面里能读到
`data-windows-titlebar`，自绘 caption 生效。欢迎窗在加 `0016` 之前是「页面 600x700 + 29px 原生菜单栏」，
现在 600x729 全给页面（`useContentSize` 在隐藏菜单栏后不重算外框尺寸）。
第一版 `0016` 没有那个守卫，在 Linux 上主进程会抛 `Titlebar overlay is not enabled` 并弹异常框，
表现为「窗口在、Host 不启动」，原因与排查见「注意」。

## 让插件市场认得宿主版本（0017）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0017-desktop-host-resources-path.patch` | `src/node-environment.ts`、`src/main.ts`、`desktop-host/src/index.ts`、2 个 spec | Linux 的 Host 跑在 primary-runtime 的真 Node 上（0008），进程里没有 Electron 的 `process.resourcesPath`，dsh-market 的宿主探测（`dshHostInfo()`，靠它认出 `resources/app/dsh/node_modules/@deepseek-ai/dsh`）两路全落空 → 市场全程「宿主版本未知」。现在 shell 把打包安装的 resources 根随 `DesktopNodeRuntime.resourcesPath` 交给 Host（`desktopNodeEnvironment()` 只对 standalone 运行时展开成 `DSH_DESKTOP_RESOURCES_PATH`），Host 入口在 Electron 之外把它回填成 `process.resourcesPath` —— dsh-market 的 Electron 探测分支原样命中，#778 的嵌套候选天然覆盖本布局。Electron 运行时一字未动：它自带真值，且子进程里的值永远优先 |

`0017` 的每个文件也属于 `0008`，且它的 diff 上下文含 `0008` 新增的行，所以**只有排在 `0008` 之后才成立**
（见开头那条例外）。

## 让 Linux 也用上「玻璃」布局（0018）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0018-desktop-linux-glass-mode.patch` | `src/glass-mode.ts`（新增）、`src/glass-document.ts`（新增）、`src/main.ts`、`src/preload-windows.ts`、`src/web-document.ts`、`tests/{glass-mode,glass-document,main-startup,preload-windows.client,web-document}.spec.ts`、`packages/client/ui-layout/{src/client/AppFrame.tsx,src/client/AppFrame.module.css,tests/app-frame.client.spec.tsx}`、`packages/client/ui-sidebar/{src/client/SidebarRoot.tsx,src/client/SidebarRoot.module.css,tests/sidebar-root.client.spec.tsx}`、`packages/client/ui-plugin-manager/src/client/PluginManagerPage.module.css`、`packages/client/ui-schedule/src/client/TaskManagerPage.module.css` | `DSH_DESKTOP_GLASS=1` 时主窗口改成 `transparent: true` + `#00000000`，preload 通过 `additionalArguments` 拿到 `--dsh-desktop-glass` 后直接返回（不装 caption 标记，于是保持 Web 布局），主进程对 Linux 打开 `setAutoHideMenuBar(true)` 并关掉菜单栏（application menu 仍在，`Alt` 可唤出）。`dsh-app://app` 的文档多一条 `headInjection`：玻璃模式把 `glassDocument(tint)` 塞进 `<head>` —— 一条 `data-dsh-glass` 标记 + 一段 `<style>`：html/body/#root 与 grid frame 清成全透明，侧栏套用从 `packages/client/ui-layout/lib/client.js` 抄来的 macOS 材质（渐变 + `color-mix(… 40%/50%, transparent)`），内容区/右栏/底部保持 `--dsw-alias-bg-base` 实色，侧栏自己的面板与 New Session 按钮按 macOS 的做法重新上色；会话列表底部的渐隐遮罩（`[class*="scrollFade"]`）按 macOS 的做法隐藏 —— 它的渐变终点是不透明的侧栏填充色，压在透明栏上会变成一道实色带 |

为什么玻璃材质整段走注入的 `<style>` 而不是客户端代码：UI 是打包好的客户端产物，类名是 CSS Module
哈希，只能靠后缀与结构选择器命中（`[class*="sidebarCol"]`、`[class$="newSession"]`、
`[class*="sidebarCol"] > div > [class*="_root"]`），换个客户端包就得跟一个补丁。只有侧栏半透明：整窗透明
的文字可读性在 KDE / GNOME 上没有模糊兜底；**darwin 的视觉规则（vibrancy 材质、窗口拖拽）仍然不复用**。

布局 frame 用 `div:has(> [class*="sidebarCol"])` 定位，不用 `[class*="_frame"]` —— 后者会连附件缩略图、
子代理卡片、右侧栏浏览器的同名后缀一起清掉。菜单也照 macOS：透明窗上 `backdrop-filter` 拿不到不透明底，
45% 的填充会让侧栏文字直接透出来，所以把 darwin 才显示的 `[data-menu-backing]` 垫层放出来（CSS anchor
定位到菜单矩形，背景 `--dsw-alias-bg-base`）。

这条「透明窗 + 从 `serveWebDocument()` 往 `<head>` 注入样式 + 用子串选择器命中哈希类名」的路线，
[issue #6](https://github.com/ffyfox/dsh-desktop-linux/issues/6) 里
[Mooling0602 的 `desktop-window-glass.mjs`](https://github.com/Mooling0602/nix-packages/blob/main/pkgs/by-name/de/deepseek-harness-desktop/desktop-window-glass.mjs)
先做过一版，本仓库评估玻璃模式时参考过它。本补丁只取了这三点。材质数值（40% / 50% / 90%）与渐隐遮罩的
处理来自上游 darwin 规则，整页透明和 `composerSeat` 的清法没有采用，布局改造（收起列宽、座椅、顶部让位）
也不在那一版里。

侧栏收起布局走的是另一条路：它属于**结构**而不是材质 —— 列宽写在 frame 的 `grid-template-columns` 上，
座位由 React 条件挂载，注入 CSS 两头都够不着。所以在 `ui-layout` / `ui-sidebar` 里加
`data-platform='linux'` 分支，条件是「linux 且没有 `data-windows-titlebar` 标记」，也就是玻璃模式
（普通模式由 `0016` 打这个标记，因此完全不受影响）。与上游窄屏抽屉 `drawer` 的布局条件并存：
`AppFrame.tsx` 中 `collapsedWidth` 为 `drawer || darwin || linuxGlass || windowsTitlebar ? 0 : SIDEBAR_COLLAPSED`，
`leadingMounted` 为 `drawer || (darwin || linuxGlass) && sidebarCollapsed`；`SidebarRoot.tsx` 的
`drawer` 判断与 `stripDesktop` 并存，玻璃模式仍然把开关放在侧栏顶部、收起后交给 frame 的 `shell.leading`。

收起照官方 macOS 端：整列消失。条内锚点也照 macOS 窗口态：`.topStrip` 在 darwin
下是 `justify-content: flex-end`（红绿灯占左端、切换钮在右端），玻璃模式不加覆盖、沿用同一锚点 —— Linux
没有红绿灯，于是条的左端空着。上游那条「全屏时切换钮挪到条左端」（`[data-fullscreen] .topStrip`）只在红绿灯
被隐藏时成立，玻璃模式不用它。收起时窗口 chrome 换到左端座椅，同样与 macOS 一致。

实测几何（1280×820，KDE Plasma 6 / Wayland，DPR 2）：

| 状态 | 几何 |
|---|---|
| 展开 | 侧栏列 280px；顶部 52px 条（`.topStrip`，`margin-top:-6px` 抵消根内边距），28px 切换钮落在条的右端 `(240,11)`、中心 y25（与 macOS 窗口态同一锚点）；wordmark 经 `-12px` 回缩落在 y58–82（比原布局低 34px） |
| 收起 | grid `0px …`：侧栏列 0 宽、内容区直达窗口左缘；`shell.leading` 座椅挂载，两个 28px 按钮在 `(12,11)` / `(48,11)`，中心 y25 —— 纵向与展开态切换钮同一水平线，横向换到窗口左端（红绿灯那一侧留给座椅，与 macOS 同） |
| 让位 | 收起态发布 `--dsh-frame-leading-clearance: 84px`（会话标题左侧留白）；`--dsh-frame-top-clearance: 48px` 与 `--dsh-frame-overlay-top: 68px` 则**不分展开/收起**，与 darwin 同（见下）；列宽 0，分隔线不画 |

入口页与弹窗的让位照 darwin 的写法补齐：`--dsh-frame-top-clearance: 48px` 与
`--dsh-frame-overlay-top: calc(var(--dsh-frame-top-clearance) + 20px)`（= 68px）在
`html[data-platform='linux']:not([data-windows-titlebar])` 上**无条件**发布，两个消费者的选择器也放行
同一条件（`PluginManagerPage.module.css` 的 `.pageHead`、`TaskManagerPage.module.css` 的 `.pageHeading`）——
于是插件市场 / 任务计划页的标题在两种侧栏状态下都是 28 + 48 = 76px（不上下跳），弹窗顶部安全距 68px，
与 macOS 逐值相同。变量声明在 `html` 上（不是 frame），portal 到 `body` 的弹窗、菜单同样继承。

对照：普通模式（Windows 版样式）收起也是 0 宽 + 页面内标题行的固定控件 `(12,6)` / `(48,6)`。

浓度默认为 macOS 的两个值（浅色 40% / 深色 50%），`DSH_DESKTOP_GLASS_TINT=0..100` 同时覆盖两种主题
（`^\d{1,3}$` 校验，越界或非法回落默认）；`prefers-reduced-transparency: reduce` 时下限 90%。

实测：KDE Plasma 6 / Wayland 上视口 820→791→820（`Alt` 按下与再按一次），
GNOME 50（Ubuntu 26.04.1）、GNOME 48（Debian 13）、GNOME 50（Fedora 44）都是 783→754→783，普通模式
`Alt` 无效且 caption 仍是 40px；计算样式读数侧栏浅色 `color(srgb 0.9615… / 0.4)`、深色 `/ 0.5`、
`DSH_DESKTOP_GLASS_TINT=80` 为 `/ 0.8`，侧栏面板 `rgba(0,0,0,0)`、内容区 `rgb(255,255,255)`（深色
`rgb(21,21,23)`）、New Session `rgba(255,255,255,0.55)`，「降低透明度」下变成 `/ 0.9`。Hyprland 边缘
能量 A/B：模糊开 1 349 291 vs 关 1 963 868（约 −31%），说明真模糊确实在起作用。上游桌面单测在补丁态下
零失败（1635 通过 / 61 跳过），`build.sh --dir` 与 `--all` 均成功。收起与让位（1280×820，KDE Plasma 6 /
Wayland）读数：展开 grid `280px …`、条 52px、切换钮 `(240,11)`（条右端）中心 y25；收起 grid `0px …`、
座椅 `(12,11)`+`(48,11)` 中心 y25、侧栏列宽 0、内容区从 x0 开始；普通模式不受影响（caption 40px、收起
`0px`、控件仍在 `(12,6)`/`(48,6)`）。

## 让 Linux 走无边框窗口（0019）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0019-desktop-linux-frameless.patch` | `src/frameless-mode.ts`（新增）、`src/wayland-csd.ts`（新增）、`src/main.ts`、`src/preload-platform.ts`、`src/preload-menu.ts`、`src/preload-windows.ts`、`src/welcome-window.ts`、`src/update-overlay.ts`、`tsconfig.client.json`、`tests/{frameless-mode,main-startup,welcome-window,preload-menu.client,preload-platform.client,preload-windows.client,wayland-csd,update-overlay}.spec.ts`、`packages/client/ui-sidebar/{src/client/SidebarRoot.module.css,tests/sidebar-styles.client.spec.ts}` | `DSH_DESKTOP_FRAMELESS=1` 时主窗口加 `titleBarStyle: 'hidden'` + `titleBarOverlay`（高度 40、初始色取 `chromeFallbackFill()`），原生按钮由 Electron 自绘（见下），标题区其余部分仍由 0016 的页内 caption 提供；`windowsAppearance` 里 `setTitleBarOverlay` 的门从「只 Windows」放宽到「Windows 或 Linux 无边框」，页面实测出来的侧栏色因此也能刷到原生条上。全屏事件与 preload 的 `data-fullscreen` 监听一并放行到 Linux 无边框（全屏时原生按钮隐藏，caption 要给内容让位）。欢迎窗走同一套覆盖层（高度 42）。`preload-windows.ts` 通过自定义属性 `--dsh-windows-titlebar-x` 桥接 `env(titlebar-area-x, 0px)`，`SidebarRoot.module.css` 的 `.toggle` / `.collapsed .newSession` 叠加该变量、`preload-menu.ts` 叠加 `env(titlebar-area-x, 0px)` 整体右移，系统把按钮放左侧时侧栏控件与菜单同步避让。`wayland-csd.ts` 由 `DSH_DESKTOP_FRAMELESS` 与 Wayland 客户端状态推导并收敛帧状态变化：按 Chromium 顺序判定 Wayland 客户端、圆角判据加首次 `move` 门控（窗口 API 在第一次移动前报的是请求位置而非帧内缩），更新浮层在无边框窗口上从 caption 下方开始并按帧圆角裁切 |

**为什么不是 `frame: false`**：Electron 的 `IsWindowControlsOverlayEnabled()` 要求
`titleBarStyle === 'hidden'` **且** 创建时就带 `titleBarOverlay`。`frame: false` 单独用（不带
`titleBarStyle`）覆盖层是关的，`setTitleBarOverlay()` 直接抛
`TypeError: Titlebar overlay is not enabled`；只有成对用才会生成 `env(titlebar-area-*)` 和原生按钮。

**为什么无边框压过玻璃**：Linux 上 `transparent: true` 的窗口拿不到控件覆盖层 —— 电子层的
frame 布局对透明窗不建 client frame，`env(titlebar-area-width)` 读出来是 0，`setTitleBarOverlay()`
静默不生效。两者叠起来就是「无边框但没有关闭按钮」，所以两个变量同设时玻璃整条让位（`main.ts`
里的 `glassLayout()`），并在 stderr 打一条警告。0016 那句「窗口装饰一律不动」到这里有了例外：
只有 `DSH_DESKTOP_FRAMELESS=1` 时才由我们接管整条标题区。

**欢迎窗的字色**：固定 `#0F1115`，与 Windows 分支一致。Linux 欢迎窗底色固定 `#FFFFFF`，
深色主题下叠上去的是 50% 深色 tint（中灰），浅色字反而看不清；要改成跟随主题得连底色一起改，
不在这条补丁里。

**按钮是谁画的**：Electron 44 在 Linux 上自绘 WCO 按钮（`FreedesktopNavButtonProvider`：图标取自
freedesktop 图标主题，样式按 GTK 主题名选 —— `Breeze*` → Breeze 风格（18px、静止无底、悬停反色），
其它（含读不到）→ Adwaita 风格（24px 圆盘）），**不是** KWin / GNOME 自己那套控件。数量与位置取
系统的 GTK 装饰布局（Chromium 的 `NavButtonProvider`），本机 `gtk-decoration-layout=:close` →
只有一个关闭钮，KWin 自己的 `SE`/`HX` 不参与。

**测试时的坑**：主题名走 `GtkSymbolicIconProvider::GetThemeName()`（读 `gtk-theme-name`）。给实例
隔离 `XDG_CONFIG_HOME` 会把 GTK 配置一起隔离 —— 目录里没有 `gtk-3.0/settings.ini` 时主题名回落
Adwaita，按钮从「无底 ✕」变成「24px 圆盘」。2026-10-30 用同版本 Electron 探针做过 A/B：真实
`XDG_CONFIG_HOME` 下是 Breeze 风格无底 ✕，空目录下是 Adwaita 圆盘；所以验按钮样式时不要隔离
`XDG_CONFIG_HOME`（只隔离 userData 可以用 `--user-data-dir`）。

**左置按钮适配**：LightningCSS 的 CSS Modules 默认只豁免内置白名单 `env()` 名称（如 `safe-area-inset-*`），在 `.module.css` 中直写 `env(titlebar-area-x, 0px)` 会被当作局部标识符混淆成 `<hash>_titlebar-area-x` 从而回落 `0px`；因此由 `preload-windows.ts` 在根元素设置自定义属性 `--dsh-windows-titlebar-x: env(titlebar-area-x, 0px)` 桥接，`SidebarRoot.module.css` 的 `.toggle`（`12px`）与 `.collapsed .newSession`（`48px`）叠加 `var(--dsh-windows-titlebar-x, 0px)`，`preload-menu.ts` 的菜单宿主（不走 CSS Modules）叠加 `env(titlebar-area-x, 0px)` 随 `var(--dsh-windows-menu-start, 48px)` 一并右移，避免左侧窗口按钮遮挡侧栏控件及菜单。在右置按钮、普通模式与全屏下 `env(titlebar-area-x, 0px)` 回落为 `0px`，原有落位保持不变。

本机实测（Hyprland 0.56.2 / Wayland，DPR 2，显示器 3072×1920；1280×820 的主窗被平铺成 757×903）：

| 场景 | 读数 |
|---|---|
| 无边框主窗 | `data-windows-titlebar` 在、`data-dsh-glass` 不在、`env(titlebar-area-width)` = 718 / 内宽 757（右侧 39px 留给原生关闭钮）、`.frame` 的 `padding-top` = 40px；侧栏收起态下 New Session 在 x=48、菜单从 x=84 起 |
| 全屏（合成器发 xdg_toplevel fullscreen） | `html[data-fullscreen]` 出现、视口 1536×960；退出后标记消失、视口回到 757×903 |
| 两个变量同设 | stderr 一条 `dsh desktop: DSH_DESKTOP_FRAMELESS=1 takes precedence over DSH_DESKTOP_GLASS; glass mode is off`；`data-dsh-glass` 不在、覆盖层宽度仍是 718 |
| 只设玻璃 | 与改前一致：`data-dsh-glass` 在、`data-windows-titlebar` 不在、覆盖层宽度 0、侧栏 `color(srgb … / 0.4)` |
| 欢迎窗 | 620×720，右上角有原生关闭钮；同一窗口的普通模式是 600×729、没有关闭钮（Hyprland 不画标题栏，这正是 issue #9 的场景） |

KDE Plasma 6（kwin_wayland / Wayland，DPR 2，1536×960）上复核了同一份 `--dir` 产物：

| 场景 | 读数 |
|---|---|
| 主窗 | frame = client = 1280×820（普通模式同一窗口的 frame 比 client 高 28px，那 28px 就是原生标题栏）、`env(titlebar-area-width)` = 1241 / 1280、caption `padding-top` 40px |
| 双击 caption 条 | 最大化到 1536×914（面板占 46px），覆盖层随之变 1497；再双击回到 1280×820 |
| 拖拽 caption 条 | 窗口跟着指针走（128,47 → −16,232），说明 `-webkit-app-region: drag` 在 KDE 下也生效 |
| 欢迎窗 | 恰好 600×700（与 `useContentSize` 的请求一致），右上角有原生关闭钮，`env(titlebar-area-width)` = 561 / 600 |

Hyprland 那张表里欢迎窗是 620×720、KDE 是 600×700 —— 同一个 `useContentSize`，两边的边框计算不同，都不影响布局。
GNOME 的桌面双击最大化还没跑（留给实机复核与三发行版矩阵）。
左置按钮复验（0.2.2-rc.5 `--dir` 构建，1280×820，隔离 keyfile）：Hyprland 0.57.2 / Wayland（`adw-gtk3`）下 `close,minimize,maximize:` 测得 `env(titlebar-area-x)` = 113（覆盖层宽 1167 / 1280），展开态切换钮 x=125..153、菜单 x=161 起，收起态切换钮 x=125..153、New Session x=161..189、菜单 x=197 起；对照 `:close` 下 `env(titlebar-area-x)` = 0（覆盖层宽 1241 / 1280），展开态切换钮 x=12..40、菜单 x=48 起，收起态切换钮 x=12..40、New Session x=48..76、菜单 x=84 起。KDE Plasma 6 / Wayland（`Breeze`）下 `close,minimize,maximize:` 测得 `env(titlebar-area-x)` = 72（覆盖层宽 1208 / 1280），展开态切换钮 x=84..112、菜单 x=120 起，收起态切换钮 x=84..112、New Session x=120..148、菜单 x=156 起，双态均无重叠。

## Arch 包与 deb/rpm 构建树的差异（无害）

同一份上游代码、两套构建入口（`build.sh` 在 `upstream/` 里出 AppImage / deb / rpm，`makepkg` 在
`pkgbuild/src/deepseek-harness-dsh-<tag>/` 里出 Arch 包）产出的树不逐字节相同。除 `package.json` 里
`dshBuildCommit` 记错那处真缺陷（已由 `0012` 修掉）外，其余差异**全部同源**：客户端打包会把源码
绝对路径写进 CSS-module 产物，路径一变，派生的哈希与清单跟着变。

| 差异 | alpha.2 实测规模 | 为什么无害 |
|---|---|---|
| 打包后 JS 里的 `\0dsh-css:` / `\0dsh-inline-css:` / `\0dsh-global-css:` **绝对路径注释**，以及由它派生的 CSS-module **类名前缀**（`.pnC3sa_row` → `.hlg3va_row`，CSS 正文逐字相同） | 54 个文件（48 × `client.js` + `devtools_app.js` + `client.{excel,frontmatter-fields,pdf,terminal,page}.js`） | 注释是构建期元数据，类名两侧各自自洽 |
| devtools 的**哈希 chunk 文件名** | 94 对改名 | 文件名 = 内容哈希，引用它的清单同步生成 |
| `desktop-runtime.json` / `resource-manifest.json` 里上述文件的 `bytes` / `sha256` | 2 个文件 | 记的是各自树里的真实值 |

另有两处**有意为之**的不同，既不是缺陷也不是疏漏：

- `resources/app/package.json` 的 `homepage` 只在有 fpm 目标（deb/rpm）时写入
  （`electron-builder-config.mjs` 的 `linuxPackages === undefined ? {} : { homepage }`）；Arch 包是
  `--dir` 构建，不需要 deb/rpm 的 control 字段。
- `resources/apparmor-profile` 同理只由 fpm 的 deb/rpm target 拷进 `linux-unpacked`；Arch 包改在
  发行版标准位置提供等价 profile：`/etc/apparmor.d/deepseek-harness`（见 `PKGBUILD` 的 `package()`）。

这些差异都不影响运行：`dshBuildCommit` / `dshBuildDirty` 是上游写进清单的溯源字段（production 上传
据此决定要不要给 `desktop-v<版本>` 打标签），安装树里没有代码读它；`homepage` 只被 electron-builder
用来填 deb/rpm 的 control。

## 注意

- **补丁全部应用后，上游自己的桌面单测应该零失败 —— 这是「改了行为、spec 有没有跟上」的判据。**
  实测 2026-11-19（0.2.2-rc.5）：`~/.local/share/dsh-pnpm-11/node_modules/.bin/pnpm exec vitest run
  apps/desktop/tests apps/desktop-host/tests`
  → 0 失败（194 个文件：189 通过 / 5 跳过；2413 个用例：2348 通过 / 65 跳过）。**改源码行为的补丁要在同一个补丁里改掉对应的 spec**（`0008`、
  `0016` 就是这么做的，其中 `0008` 与 `0016` 共用 `tests/main-startup.spec.ts`）。`scripts/` 与 CI
  都不跑上游单测。跑的时候注意三点：用隔离版 pnpm 11（`~/.local/share/dsh-pnpm-11/node_modules/.bin/pnpm`，
  本机 11.7.0；本机 `/usr/bin/pnpm` 已是 12.14.0 的 ELF、`~/.npm-global/bin/pnpm` 是 9.15.4，
  两者都会遮蔽它）；摘掉代理（`env -u NODE_OPTIONS -u NODE_USE_ENV_PROXY -u http_proxy -u https_proxy
  -u HTTP_PROXY -u HTTPS_PROXY`），否则 `host-process.spec.ts` 会因 `127.0.0.1` 也被代理接管而多红几个；
  **先确认 `native/system/packages/<host>/bin/` 里 `prebuilds.json` 声明的二进制都在**（linux-x64 是
  `landlock-run` + `glibc/system.node` + `musl/system.node`）—— `build:native-system` 带
  `--host-addon-only`，只编 host 的 Node-API 件，`landlock-run` 与 musl 那份要用 musl 工具链另编；
  缺了它上游 `flock-entry.ts` 会走 `node $npm_execpath` 重建，碰上二进制入口的 pnpm 就报
  `SyntaxError: Invalid or unexpected token`（2026-10-17 在这台机器上撞到过：本机没有 musl 工具链，
  这次是把已打包产物里的同源二进制补进树里才跑通的，15 个用例全在 `macos-notarization-proxy.spec.ts`）。
- **`PKGBUILD` 的 `aarch64` 支持只做原生构建。** `build()` 与 `package()` 按 makepkg 的 `$CARCH` 分支：
  `x86_64` → `linux-x64` / `linux-unpacked`，`aarch64` → `linux-arm64` / `linux-arm64-unpacked`
  （arm64 目录名由补丁 `0009` 决定，与 `scripts/verify.sh` 一致）。交叉构建在 prepare 阶段执行目标平台运行时就会失败，CI 的 `arch` job 由 `ubuntu-latest` 与 `ubuntu-24.04-arm` 各自原生出包。
- **同步上游时若某个 spec 的 hunk 合不上，允许先把它摘掉，让核心改动先过去。** 上游重写 `tests/*.spec.ts`
  时，宁可回落到「单测红着、但行为改动完整」，也不要为了保住 hunk 而把行为改动丢掉或跳过。
- **「构建用的 pnpm 入口必须是 JS」是上游遗留的写法，不是我们造成的，我们也没为它加补丁。**
  上游三处 desktop 脚本无条件 `node $npm_execpath`：`apps/desktop/scripts/package-target.ts`、
  `flock-entry.ts`、`dev.ts`。npm 与 corepack 装的 pnpm 入口是 `.mjs`，所以上游 CI 与本机都没事；
  但**官方 standalone 安装器（pnpm.io 首推那条）与 Homebrew 给的是编译好的二进制**，那种 pnpm 交给
  脚本的 `npm_execpath` 就是二进制本身，打包阶段会报 `SyntaxError: Invalid or unexpected token`
  （2026-10-15 在 Ubuntu 26.04.1 的 live VM 里用真实 `build.sh --all` 复现过）。**不加补丁的理由**：
  它不属于 Linux 移植，而且上游一旦自己修，我们的补丁就会变成重复改动、下次同步必然冲突。
  挡在门口的是 `scripts/select-pnpm.sh`（`build.sh` / `dev-desktop.sh` 共用）：选 pnpm 时先照上游
  那三处的写法探一次入口，不合用就退到 `~/.local/share/dsh-pnpm-11`，都没有再打印安装命令。
- **dev 模式也需要 `0001`**——`dev.ts` 虽然不走 `package-target.ts`，
  但会调用 `resolveDesktopBuildTarget()`，Linux 上抛 `unsupported target linux-x64`。
- 上游有手写的 `.d.mts` 声明文件，改 `.mjs` 的 JSDoc **不够**，类型联合必须同步改 `.d.mts`，
  否则 `tsc` 报错。
- **`DSH_DESKTOP_NODE_ELECTRON` 的缺省值必须保持「Electron」**。调用方清空环境时不会带上
  这个变量，缺省若回落到 standalone，macOS / Windows 的包脚本会以 GUI 模式起 Electron。
- `0003` 与 `0005` 都涉及策略：`0003` 决定「产物里嵌不嵌」，`0005` 决定「打包期要不要 origin」。
  一条改动只属于一个补丁，所以这两半分在两处。
- **`DSH_DESKTOP_TARGET_FORMATS` 刻意不进 `.env.linux` 白名单**。它是「这次构建打什么」的
  选择器（和 `DSH_DESKTOP_TARGET_PLATFORM` / `_ARCH` 同类），不是发布设置；进了文件反而会让
  `build.sh --deb` 被文件里的值盖掉。
- **Linux 不接上游的 `DSH_PACKAGING_PRESET`（`0005`）。** 预设是给「打包机上的签名凭据」用的
  （`presets/<test|production>.env` + `secrets/<平台>-signing.env`），而 Linux 产物无签名，
  我们的 PKGBUILD 写的是 `.env.linux`、从不设 `DSH_PACKAGING_PRESET`。所以 `0005` 让 Linux 撞上预设时
  直接报一条可行动的错，而不是顺着上游的三目去读一份不存在的 `macos-signing.env`。
- **`0012` 是唯一为「非 git 源码」存在的补丁**。上游两条路都要 git：`scripts/build.ts` 经
  `repositoryCommitHash()` 读 `HEAD`（有 `DSH_CLIENT_COMMIT_HASH` 环境变量出口，不用改），
  `apps/desktop/scripts/package-target.ts` 的打包入口无条件调 `readDesktopBuildCommit()`（没有出口，
  所以要 `0012`）。PKGBUILD 从 release 源码包构建，所以两个变量都由它显式给出，`_DIRTY=1` 也是事实
  ——这个构建确实打了补丁。
- **`0012` 的判据必须是「环境变量优先」，不能只作「不是 checkout 时的兜底」。** makepkg 的 `$srcdir`
  是 `pkgbuild/src/deepseek-harness-dsh-<tag>/`，而 `pkgbuild/` 就在本仓库里，
  `git rev-parse --is-inside-work-tree` 探针会成功，于是「先探针」的写法把**本仓库的 HEAD** 当成
  上游提交写进 `dshBuildCommit`：alpha.2 那份 Arch 包实测记 `a99ac6be…`，应记 `d7432673…`
  （deb/rpm/AppImage 不受影响，`build.sh` 从 `upstream/` 构建、根本不设这两个变量）。
- **补丁按序应用时只有 offset、没有 fuzz，但会留下两个 `.orig`。** `electron-builder-config.mjs`
  （0003 + 0013）与 `src/main.ts`（0008 + 0013 + 0016 + 0017）被多个补丁触及，它们的 diff 取自「基线 +
  只有这一个补丁」的隔离树，所以后一个补丁落下去时命中 offset；GNU patch 遇到 offset 会各留一份
  `<文件>.orig`。备份不进产物，两个文件最终内容与开发工作树逐字节一致。
- **rc.2 新增的 `prepare:cli` 在 Linux 上整块跳过（`0004`）。** `prepareDesktopCli(dir, platform)` 的
  形参是 `'darwin' | 'win32'`（不含 `linux`），它拷的 `apps/desktop/cli/dsh` 是 macOS 脚本
  （内部 exec `$resources/../MacOS/DeepSeek Harness`），`link-entry` 要 clang 编译，
  `command-manager-entry.js` 走 `/usr/local/bin/dsh` 与 PowerShell；而 rc.2 里触发这套东西的菜单项
  本身就 gate 在 `darwin` / `win32`。Linux 上没有入口，硬跑还会把 macOS 启动器塞进产物，
  所以这一段包进 `if (platform !== 'linux')`，Linux 不产出 `runtime/cli`。
- **`dsh` CLI 找 runtime 的路径取决于 asar 开不开（`0008` 的教训）。** `apps/desktop-host/src/cli.ts`
  自己推 supportDir：打成 asar 时 payload 在 `resources/app.asar/dsh`，runtime 就挨着归档文件
  （`resources/runtime`）；Linux 关掉 asar 后 payload 是真实的 `resources/app/dsh`，同一段推导
  会指向 `resources/app/runtime` —— 那里没有 pnpm，`dsh … plugin` 直接 `MODULE_NOT_FOUND`。
  所以非 asar 分支改为上一级找 `resources/runtime`。上游 0.2.1-alpha.2 新增的打包后冒烟
  （直接跑 `resources/app/dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js plugin …`）
  正好踩在这个入口上，才把它暴露出来。
- **可见性问题先用 `isVisible()` 量，别先猜合成器（`0015` 留下的手法，该补丁已随 0.2.2-alpha.2 作废）。**
  用 `--remote-debugging-port=9222 --inspect=9229` 起应用，从主进程读 `BrowserWindow.getAllWindows()`：
  当年关窗后浮层窗口存在、`modal: true`、内容与按钮位置都对，但 `isVisible()` 是 `false`；手动 `show()`
  一次即正常显示且可用鼠标点。Debian 13（GNOME 48.7）与 Ubuntu 26.04（GNOME 50.1）都如此 —— 结论是
  Wayland 下不报首帧，补丁加了一次 `did-finish-load` 的兜底。0.2.2-alpha.2 上游把浮层换成
  `WebContentsView`（挂在主窗口里、没有自己的窗口生命周期），这条路径整体消失，补丁因此作废。
- **托盘的依赖问题全在 ELF 之外。** 实测（Electron 44 二进制）：Linux 托盘走进程内的
  StatusNotifierItem（二进制里有 `StatusIconLinuxDbus`、`org.kde.StatusNotifierWatcher`），
  全库没有 `appindicator` 字样，`ldd` / `NEEDED` 里也没有，所以**不需要** libappindicator。
  但托盘菜单要 `libdbusmenu-glib.so.4`——那个库名和 `dbusmenu_*` 符号名都在二进制里，
  却不在 `NEEDED` 里（1519 个未定义动态符号里没有它），即 dlopen。缺了它图标照出、菜单是空的，
  等于没有退出入口，而 `ldd` 和 namcap 都看不见，所以它由 PKGBUILD 显式写进 `depends`。
- **Linux 上可靠的是托盘菜单，不是单击图标。** 实测把 SNI 的 `Activate` 调过去，Electron 的
  `tray.on('click')` 没有触发（StatusNotifierItem 宿主有权把左键用来弹菜单）。`DesktopTray`
  保留 click 处理是给 Windows 的；Linux 上「打开」走右键菜单，`verify.sh --runtime` 也是按
  菜单里的条目来断言。
- **托盘美术在 Linux 上刻意与 Windows 不同，Windows 那份一个字都没动。** 上游的 `tray-glyph`
  组只含鲸鱼（底在组外），渲染 Windows ICO 时会被绕方块中心放大 20% —— 因为 Windows 托盘逻辑
  尺寸是 16px，不放大就看不清。Linux 不同：托盘宿主按面板尺寸自己绘制（KDE 是 22px），1.2× 在
  那里会显得鲸鱼顶满方块。所以 `renderLinuxTrayIcon()` 按原比例渲（保留应用图标自身的留白，
  与启动器/任务栏图标观感一致），底图仍然保留，深浅面板都还有对比度。两边同源（都用
  `resources/icon-windows.svg`），改动只在渲染参数上。
- **`0016` 是「借属性」，不是「改名」。** caption 布局在客户端里是按 `html[data-windows-titlebar]`
  这个选择器激活的（`ui-sidebar` 与 `ui-layout` 里十几处 CSS/TSX 都在 `:global([data-windows-titlebar])`
  下），改名要连同一批测试一起动。所以这里只放宽平台门，代价是这些名字在 Linux 上名不副实；
  等上游哪天给 Linux 做自己的 caption，再统一命名。
- **`0016` 与 `0008`、`0013` 共用 `src/main.ts`**，所以它同样按开头那条约定、在「基线 + 只有这一个补丁」
  的隔离树里取 diff（`git diff --no-index` 两棵树，再改回 `a/`、`b/` 前缀）。
- **借 Windows 属性时，Windows 专属的 Electron 调用必须单独守卫（`0016` 的教训）。** caption 的
  布局与菜单是纯客户端行为，照搬无害；但 `windowsAppearance` 这个 handler 里有一句
  `mainWindow.setTitleBarOverlay(...)`，而窗口的 `titleBarOverlay` 只在 `win32 && primary` 时创建。
  Linux 上调它抛 `TypeError: Titlebar overlay is not enabled` —— 这是主进程里**未捕获**的异常，
  由 IPC 监听器抛出，不是启动链自己抛的；而启动链的顺序是先 `await navigateMain(...)` 建主窗口、
  再 `backend.start(...)` 拉起 Host，异常正好落在这两步之间，于是 **Host 从未被拉起**：主窗口已显示、
  `dsh web:` 永远不出现、`$DSH_HOME/profiles/` 不生成，连 `--remote-debugging-port` 的端点也只接受
  连接不回数据。**别把它误判成死锁或产物问题**：主进程其实空闲在 `poll`（~0.6% CPU）。排查靠
  `xdotool search --pid <pid>` 找到那个名叫 `Error` 的窗口，再 `import -window <id>` 抓下来读原文；
  探 DevTools 之前记得先摘掉本机的 `NODE_USE_ENV_PROXY`/`http_proxy`，否则 `127.0.0.1` 也会被代理拦掉。
