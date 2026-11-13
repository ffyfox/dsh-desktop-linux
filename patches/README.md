# 补丁

按文件名顺序应用（见 `scripts/apply-patches.sh`），全部相对上游 `f3803c96`（tag `dsh-v0.2.2-alpha.2`）。

组织约定：**一条改动只属于一个补丁**。每个补丁都是相对同一个基线的独立 diff，改动互不重复、
按编号应用（顺序依赖见下）。补丁由 `git diff -- <files>` 从开发工作树生成；**一个文件可以被
多个补丁触及**，此时必须按「基线 + 只有这一个补丁」的隔离树取 diff，否则会把另一个补丁的
hunk 一起带进来。

**`0017` 与 `0018` 是这条约定的两个已知例外。**

`0017` 的 5 个文件（`src/node-environment.ts`、`src/main.ts`、`tests/host-process.spec.ts`、
`tests/node-environment.spec.ts`、`desktop-host/src/index.ts`）全部也属于 `0008`，而且它的 diff 上下文含
`0008` 新增的行（`resourcesPath?: string` 紧挨着 `0008` 加的 `readonly electron: boolean`），所以它单独
打在干净基线上会直接 reject，只有排在 `0008` 之后才成立 —— 现有系列靠「按文件名顺序」恰好满足。
重生这类补丁要走两阶段：先在「新基线 + 前置补丁」上重算，再叠它自己的增量。

`0018` 同理但更轻：18 个文件里 4 个（`src/main.ts`、`src/preload-windows.ts`、`tests/main-startup.spec.ts`、
`tests/preload-windows.client.spec.ts`）已属于 `0008` / `0016`，而 `preload-windows.ts` 的 hunk 正落在
`0016` 放宽平台门的那几行上，所以它也只有排在 `0016` 之后才成立；另外 14 个是本系列第一次触及
（`src/glass-mode.ts`、`src/glass-document.ts`、`src/web-document.ts`、`tests/glass-mode.spec.ts`、
`tests/glass-document.spec.ts`、`tests/web-document.spec.ts`，以及 `packages/client/ui-layout` 的
`AppFrame.tsx` / `AppFrame.module.css` / `tests/app-frame.client.spec.tsx`、`packages/client/ui-sidebar`
的 `SidebarRoot.tsx` / `SidebarRoot.module.css` / `tests/sidebar-root.client.spec.tsx`，以及 `ui-plugin-manager` / `ui-schedule` 的两个页面样式表
`src/client/PluginManagerPage.module.css` / `src/client/TaskManagerPage.module.css`），
其中 4 个是新增文件。

已验证（0.2.2-alpha.2）：这一轮是完整同步 —— 上游从 rc.4 到这个 tag 走了 2161 个提交、6944 个改动文件
（剔除 `.agents/notes` 之后：3454 新增 / 3430 修改 / 60 删除）。14 个补丁触及的文件被改过而重生；
`0010` / `0011` 逐字节未动；`0012` 只差 `index` 行的缩写宽度（新树 7 位够用、旧树要 8 位，内容一字不差，
保留原样）；`0015` 整条作废（见下方编号说明）。16 个补丁按序打在完整的上游 release 源码包
（tag `dsh-v0.2.2-alpha.2`）上，`patch -Np1`（makepkg 的 `prepare()`）与 `git apply`（`apply-patches.sh` /
CI）都干净通过，两条路打出来的树与「新基线 + 逐补丁累加」的隔离树 `diff -r` 零差异；18 条校验和由
`makepkg --verifysource` 逐条验证通过（Arch 包仍由 CI 的 makepkg job 产出，本机不整包）。
`pnpm-lock.yaml` 这一轮被上游改过（31551 → 34022 行），`apps/desktop/package.json` 新增
`dsh-official-bundles`、`dsh-plugin-manager`、`dsh-util-file-drag`、`zod`、`tencentcloud-sdk-nodejs-teo`
五个依赖；根 `engines` 从 `^22.19.0 || >=24.0.0` 抬到 `>=24.9.0`，README 的 Node 门槛跟着改。
`pnpm run build:official` 的 9 道门随 `build.sh --all` 一起跑过；其中 host aggregate check 曾因 `0008`
漏改两处 spec 调用点报 `TS2345`，补上后复跑全绿。
上游桌面单测在补丁态下**零失败**（182 个文件：177 通过 / 5 跳过；2115 个用例：2052 通过 / 63 跳过）——
**跑之前必须摘掉代理**，否则 `host-process.spec.ts` 里那条「Host 停掉后 fetch 该失败」会拿到代理的 502
（见下「注意」）。`build.sh --all` 4 分 30 秒出齐三件套：AppImage 361 945 562 B（sha256 `0748201c…`）、
deb 291 689 160 B（`d0f96ab4…`）、rpm 241 742 603 B（`e330e7c3…`），打包后的冒烟也过 —— CLI 离线装插件
与卸载、`dsh web:` 起得来、Office 三种格式（DOCX / XLSX / PPTX）转 PDF 与技能 CLI 发现。
`verify.sh` 静态 **21 通过 / 0 失败 / 11 跳过**，`verify.sh --runtime` **35 通过 / 0 失败 / 10 跳过**
（9 个是 rc.2 / rc.3 / rc.4 的旧产物按当前基线跳过，1 个是 3080 没在监听），活体部分实测：与在跑的桌面端
并存（隔离 userData），Host 在 127.0.0.1:46399 监听（`--port 0`，端口由系统分配）、`dsh-app://` 出 UI
（1069 个 DOM 节点）、Linux 自绘标题栏与页内 caption 菜单宿主都在场（`0016`）、Host 跑在 primary-runtime
的真 Node 上且收到了安装树的 resources 根（`0017`）、2 个渲染进程都在独立 user namespace 且 seccomp 生效、
托盘注册且菜单读到 2 个带产品名的条目、`profiles/desktop` 已建立、共享根出现工作区存储与凭据、
`profiles/web` 哨兵未被触碰、真实 `~/.dsh/profiles/desktop` 未被改动。
产物里 `resources/runtime/cli` 不存在、`resources/app/dsh/desktop-runtime.json` 的 `release.version` 是
`0.2.2-alpha.2`（`hostProtocolVersion` 仍是 4）、`resources/app/package.json` 的 `dshBuildCommit` 记的是
上游 `f3803c96…`（`dshBuildDirty: true`，不是本仓库的提交），正是 0004 的 Linux 闸门、0008 的运行时选择与
0012 的「环境变量优先」在起作用。

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

上游同步记录：rc.2 → 0.2.1-alpha.1 只有 3 个文件变过（`pnpm-lock.yaml`、
`apps/desktop-host/src/index.ts`、`apps/desktop/package.json`），对应 0006 / 0008 / 0014 三个补丁重生，
其余 12 个逐字节未动。0.2.1-alpha.1 → 0.2.1-alpha.2 上游动了 3226 个文件（+114987/−28177），
11 个补丁触及的文件被改过而重生（0002 / 0003 / 0004 / 0005 / 0006 / 0007 / 0008 / 0009 / 0010 /
0013 / 0016），0001 / 0011 / 0012 / 0015 四个逐字节未动。重生时上游的吸收与重构逐处裁定：
`0002` / `0003` 里「放宽 `--unsigned` 的平台检查」被上游整条移除（unsigned 现在是通用的，macOS 也能出
unsigned 构建），`0003` / `0005` 的 `policy` 条件要与上游新增的「本地 macOS unsigned 构建不嵌策略」
合成一条，`0009` 的 `checkPnpm()` 被上游搬进新文件 `tests/fixtures/pnpm-smoke.mjs` 而跟着搬家，
`0004` 的 `prepare-runtime.ts` 要落在上游拆分出的 `prepareElectron()` / `prepareCli()` 结构上
（`runtime/bin/node` 的拷贝因此从 `prepareCli()` 里提出来，Linux 仍然要有这个启动器）。

0.2.1-alpha.2 → 0.2.1-alpha.3 上游动了 852 个提交、2200 个改动文件，另加 584 个新增、19 个删除。
主战场正是桌面端的打包/发布流水线：新增 `apps/desktop/{config,packaging,publishing}/`，新脚本
`desktop-publish*.ts`、`desktop-release-store.ts`、`rollback-desktop-channel.ts`、`update-channel.ts`、
`verify-retained-desktop.ts`、`desktop-ci-version.mjs` 等；`loadDesktopPackageEnvironment()` 多了第 4 个参数
与 `DSH_PACKAGING_PRESET` / `DSH_PACKAGING_CONFIG_DIR` 预设机制，读文件的逻辑抽成
`readSettings(path, accepts)`；产物目录改由新的 `desktopArtifactOutput()` 决定；更新通道从写死
`nightly` 改成 `nightly` / `latest`；新增 `--skip-notarization`。补丁触及的 52 个文件里 19 个被改过，
12 个补丁重生（0001 / 0002 / 0003 / 0004 / 0005 / 0006 / 0007 / 0008 / 0009 / 0013 / 0016 / 0017），
0010 / 0011 / 0015 逐字节未动，0012 只差 `index` 行的缩写宽度（内容一字不差，保留原样）。
**上游仍然没有 Linux**：目标联合类型还是 `mac-arm64 | mac-x64 | win-x64`，`linux-x64` 仍只由
`0001` / `0002` 提供。四处要语义裁定：`0001` 的 `desktopTargetBuildPaths()` 多了 `unnotarizedArtifacts`
（取上游新 `@returns`，只往 `@param` 加 `linux-x64`）；`0003` 的产物命名与输出目录改用 `output.suffix` /
`output.directory`（我们的 `asar: resolvedPlatform !== 'linux'` 保留在原处）；`0005` 的
`desktop-package-environment` 整个重构（Linux 分支落在上游新的 `readSettings(path, accepts)` 结构上）；
`0009` 的 `smoke-packaged-runtime.ts` 改用上游新的 `resolveDesktopPackageTarget()` 判平台，
产物目录跟着换 `desktopArtifactOutput()`。

还有一处**不是靠读 diff 看出来的，是构建期抓出来的**：上游这次新增的 `desktop-release-store.ts` 把
保留清单的 `target` 又写了一遍窄联合（`mac-arm64 | mac-x64 | win-x64`），而新的 `retain-desktop-ci.ts`
把 `resolveDesktopBuildTarget()` 的结果直接交给它，于是 `tsc -p tsconfig.host.json` 这个 host 聚合门报
`TS2322`。它的注释本来就写着「Storage accepts every Desktop target」，所以是放宽 schema、不是加类型断言；
这一处并进了 `0001`（同一个「目标模型加 linux-x64」的职责）。**教训：光看补丁触及的 52 个文件不够，
上游新写的文件也会引用我们放宽过的类型**，同步后必须实跑一遍构建门。

0.2.1-alpha.3 → 0.2.1-alpha.4 上游动了 89 个提交、831 个改动文件（+22232/−2044），主战场是新的插件市场：
新增 `apps/plugin-market-generator/` 整个应用与 `packages/boot/plugin-market` 包，插件兼容性改按
`engines.dsh` 判断（`packages/boot/app-boot/src/plugin-compatibility.ts` 重写），并给可选 bundle 名单
加了 `@deepseek-ai/dsh-experimental-plugin-market-bundle`。`pnpm-lock.yaml` 与根 `package.json` 都改了，
所以同步后 `pnpm install --frozen-lockfile` 必须重跑。补丁触及的 58 个文件里只有 2 个被改过：
`apps/desktop/package.json` 只换了版本号，`apps/desktop/scripts/desktop-release-store.ts` 把 `sourceRef`
的正则放宽成 `.min(1)` 并补了一条 production 专用的 `.refine(...)` —— 与我们改的 `target` 联合不在同一段，
hunk 的上下文根本没碰到它。这版还有一处**正好落在 Linux 上**的上游修复：启动命令前的重复检查被砍掉，
降低启动开销、改善较旧 systemd 环境的兼容性。**上游仍然没有 Linux**：目标联合类型还是
`mac-arm64 | mac-x64 | win-x64`，`linux-x64` 仍只由 `0001` / `0002` 提供。

0.2.1-alpha.4 → 0.2.1-alpha.5 上游动了 36 个提交、300 个改动文件（+2444/−597，22 个新增、0 个删除），
`pnpm-lock.yaml` 没动 —— 依赖集合不变。大头是上游自己的 Windows/macOS 打包发布流水线：新增
`desktop-publish-qualification.{mjs,d.mts}`、`preflight-desktop-publish.{mjs,d.mts}`、
`windows-runner-task.ps1` / `run-windows-runner-task.ps1` 与一个新 spec
（`desktop-publish-preflight.spec.ts`），并把「COS 桶必须未开版本化」
写成发布前提。补丁触及的 58 个文件里只有 1 个被改过：`apps/desktop/package.json` 只换了版本号
（第 4 行），而我们 `0006` 的 hunk 在第 35 行、上下文一行没碰 —— 所以这一轮只重生 `0006`，结果与
原版**只差 `index` 那一行**、字节数相同（767 B），其余 15 份逐字节未动。这版还有一处**正好落在
Linux 上**的上游修复：右侧栏收起时在输入框按 Page Up 会让整个界面向左偏移（Windows 和 Linux 都会）。
**上游仍然没有 Linux**：目标联合类型还是 `mac-arm64 | mac-x64 | win-x64`，`linux-x64` 仍只由
`0001` / `0002` 提供。

0.2.1-alpha.5 → 0.2.1-rc.1 只有 4 个提交、355 个文件（+355/−355），而且**每一处都只是一行**：355 个
`package.json` 的 `"version"` 从 `0.2.1-alpha.5` 改成 `0.2.1-rc.1`，另 9 个 vendor 包各自升一个小版本
（cordis 4.0.5、cosmokit 1.8.6、group 1.0.5、hmr 1.0.20、include 1.0.10、loader 1.0.6、
logger-console 1.0.5、schemastery 3.18.5、timer 1.1.7）。**没有任何源码、配置或 lockfile 改动**
（`pnpm-lock.yaml` 没动，依赖集合与 alpha.5 完全一致）。补丁触及的 58 个文件里只有
`apps/desktop/package.json` 变了（第 4 行版本号，`0006` 的 hunk 在第 35 行、上下文一行没碰），
所以这一轮也只重生 `0006`，结果与原版**只差 `index` 那一行**、字节数相同（767 B），其余 15 份逐字节
未动。这一版没有任何功能或修复改动，本质是上游把攒好的 0.2.1 内容收敛成候选版。**上游仍然没有
Linux**：目标联合类型还是 `mac-arm64 | mac-x64 | win-x64`，`linux-x64` 仍只由 `0001` / `0002` 提供。

0.2.1-rc.1 → 0.2.1-rc.2 有真实内容：9 个提交、300 个文件（+2569/−651，26 个新增、0 个删除）。
两处功能：DeepSeek-V4.1-Flash-1017 适配（含给 Flash 模型名加临时「1017」徽章的客户端包
`packages/client/ui-deepseek-model-label-1017`），以及 DeepSeek Search / Fetch API（走「网页搜索」设置里
的开关，`packages/web/web-deepseek-api` 挂进 base bundle）。设置卡片 `ui-settings-web-search` 的
controller 重写（+206/−49），`cordis-client-runner` 的 slot 目录加了两个槽位，docs 与 apps/web 的 e2e
同步跟上。`pnpm-lock.yaml` 没动 —— 外部依赖一个没变，只多了两条 workspace 依赖。补丁触及的 58 个文件
里只有 `apps/desktop/package.json` 变了（第 4 行版本号，`0006` 的 hunk 在第 35 行、上下文一行没碰），
所以这一轮也只重生 `0006`，结果与原版**只差 `index` 那一行**、字节数相同（767 B），其余 15 份逐字节
未动。**上游仍然没有 Linux**：目标联合类型还是 `mac-arm64 | mac-x64 | win-x64`，`linux-x64` 仍只由
`0001` / `0002` 提供。

0.2.1-rc.2 → 0.2.1-rc.3 有 6 个提交、640 个文件（+5682/−1021，50 个新增、0 个删除、6 个重命名）。
用户可见的三条：左侧栏 / 会话视图 / 右侧栏新增「更多」菜单（`ui-sidebar` 新增 `panel-pins.ts`，
`ui-sidebar-right` 新增 `guide-pins.ts` 与 `GuideMoreIcon.tsx`，`ui-entry-customization` 的菜单内容与样式
跟着改，并新增 `trackEntryClick` 埋点）、修「新会话」在切换会话后找不回未发送草稿、DeepSeek API Key
的模型列表刷新方式与账号登录对齐。`pnpm-lock.yaml` 这次动了（+69/−12），外部依赖有变化。补丁触及的
72 个文件里只有 4 个被改过：`apps/desktop/package.json`（第 4 行版本号）、`ui-sidebar` 的
`SidebarRoot.tsx` 与 `SidebarRoot.module.css`（埋点与面板区的「更多」样式，都不在 `.topStrip` 那一段）、
以及 `tests/sidebar-root.client.spec.tsx`。所以只重生 `0006`（与原版只差 `index` 那一行）与 `0018`：
`0018` 的 18 个文件里 17 个原样落位，只有那个 spec 要重取 —— 上游在同一个 macOS 用例尾部插了
`trackEntryClick` 断言，把玻璃用例那段 hunk 的上文顶掉了。**上游仍然没有 Linux**：目标联合类型还是
`mac-arm64 | mac-x64 | win-x64`，`linux-x64` 仍只由 `0001` / `0002` 提供。

0.2.1-rc.3 → 0.2.1-rc.4 有 9 个提交、369 个文件（+596/−381，1 个新增、0 个删除、0 个重命名），其中 349 个
是各个 `package.json` 的版本行。真正的内容只有两处：ACP 模式下 MCP 资源列表与 DeepSeek 账号目录的诊断
输出不再混进 stdout（`packages/mcp/mcp-client/src/connection.ts`、`packages/llm/llm-deepseek-account/src/index.ts`，
并新增 `apps/cli/tests/profiles/acp/tests/stdout.expected.e2e.ts` 159 行），以及会话视图的标签页 tooltip 只在
标签被截断时出现（`packages/client/ui-conversation/src/client/skeleton/ConversationSession.tsx` +25/−2、
`locales.ts` −2）。`pnpm-lock.yaml` 没动，外部依赖一个没变。补丁触及的 72 个文件里只有
`apps/desktop/package.json`（第 4 行版本号）变了，`0006` 的 hunk 在第 35 行、上下文一行没碰，所以这一轮
**一个补丁都没有重生**：17 份与 rc.3 逐字节相同。**上游仍然没有 Linux**：目标联合类型还是
`mac-arm64 | mac-x64 | win-x64`，`linux-x64` 仍只由 `0001` / `0002` 提供。

0.2.1-rc.4 → 0.2.2-alpha.2 是本系列最大的一次跳跃：2161 个提交、6944 个改动文件（3454 新增 / 3430 修改 /
60 删除，已剔除上游 `.agents/notes`）。主战场是 `packages/experimental`（1452 个文件，新增「开发者工具 -
统计」「变更请求与工作树」等实验插件）、`packages/client`（1325）、`apps/web`（226）与 `apps/desktop`（218）。
补丁触及的 72 个文件里 29 个被改过，14 个补丁重生（0001 / 0002 / 0003 / 0004 / 0005 / 0006 / 0007 / 0008 /
0009 / 0013 / 0016 / 0017 / 0018），0010 / 0011 逐字节未动，0012 只差 `index` 缩写；0015 因上游换实现整条作废。
六处要语义裁定：`0001` 把 `linux-x64` 补进 `desktopTargetPlatform()` 新写的映射表；`0004` 的
`prepareElectron()` 已被上游改成「函数内自己算可执行文件路径」，我们的 `(resolved, electron)` 参数顺着新签名
与新的 Windows 并行分支重落（分支里 `electron` 被解构遮蔽，改名 `electronResult`），`prepare-dsh.ts` 那处
直接取上游的 `resolveDesktopBuildTarget()` + `desktopTargetPlatform(targetName)`；`0005` 的上游正则多了
`COMPRESSION_LEVEL` / `ZIP_COMPRESSION_LEVEL` / `DOWNLOAD_PROD_EO_ZONE_ID`，`LINUX_SETTING` 与新
`|LINUX_.*` 重新合进去；`0008` 的上游 `host-process.ts` 多了一条 `parsePluginOperationRecord` 的 import，
类型导入与之并行（另外上游新加的 operation-history 用例里有 2 处 `new DesktopHostProcess(process.execPath, …)`
要跟着换成 `HOST_RUNTIME`，否则 host aggregate check 报 `TS2345`）；`0018` 的插件管理页把
`calc(28px + …)` 换成 `var(--plugin-page-top-inset)`，Linux 选择器跟着改用该变量。**上游仍然没有 Linux**：
目标联合类型还是 `mac-arm64 | mac-x64 | win-x64`，`linux-x64` 仍只由 `0001` / `0002` 提供。

`0016` 启动实测（0.2.1-alpha.2 这份产物；用隔离 `DSH_HOME` + 独立 `--user-data-dir` 起，KWin 读
`frameGeometry` / `clientGeometry`，CDP 读渲染视口）：主窗口 frame 1280x848、客户区 1280x820、
视口 820；欢迎窗 frame 600x757、客户区 600x729、视口 729。两个窗口的「客户区 − 视口」都是 0，
即都没有原生菜单栏（`frame − client` 的 28px 是 KWin 画的装饰），主窗口页面里能读到
`data-windows-titlebar`，自绘 caption 生效。欢迎窗在加 `0016` 之前是「页面 600x700 + 29px 原生菜单栏」，
现在 600x729 全给页面（`useContentSize` 在隐藏菜单栏后不重算外框尺寸）。
**第一版 `0016` 没有那个守卫**，
在 Linux 上主进程会抛 `Titlebar overlay is not enabled` 并弹异常框，表现为「窗口在、Host 不启动」，
原因与排查见「注意」。

## 让 Linux 成为受支持的 target（0001–0007）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0001-desktop-target-model-add-linux-x64.patch` | `desktop-build-paths.{mjs,d.mts}`、`desktop-auto-update-environment.{mjs,d.mts}`、`desktop-release-store.ts` | target 白名单加 `linux-x64`；`desktopTargetPlatform` 返回 `'linux'`；新增 `desktopElectronExecutablePath()`；保留清单的 schema 也认出 `linux-x64`（上游 0.2.1-alpha.3 新增的 `retain-desktop-ci.ts` 把 `resolveDesktopBuildTarget()` 的结果直接交给它，窄联合会让 `tsc -p tsconfig.host.json` 报错） |
| `0002-package-target-add-linux-x64.patch` | `package-target.ts`、`desktop-upload-plan.ts` | 打包目标表加 `linux-x64`；Linux 构建主机校验（当初还放宽了 `--unsigned` 的平台限制，0.2.1-alpha.2 起上游把那条限制整条删掉，这一半随之消失） |
| `0003-electron-builder-linux-configuration.patch` | `electron-builder-config.mjs`、`electron-builder.config.d.mts`、`tests/installer-packaging.spec.ts` | Linux 关闭 asar；显式 `executableName`；Linux 不嵌入强制更新策略；Linux 的打包格式与包元数据来自发布设置（见 `0011`）；显式钉住 deb/rpm 的 `packageName` / `packageCategory` 与 `linux.synopsis`；显式列出 deb/rpm 运行依赖并去掉 Electron 既不链接也不加载的 `libxss1` / `libXScrnSaver`（指定 `depends` 会替换整个默认数组，其余默认项保留；单测改为对着 `FpmTarget.getDefaultDepends()` 核这份数组，上游新增默认项时测试会红）；用 `appImage.executableArgs: []` 去掉 legacy 工具集写死的 `--no-sandbox`；Linux 图标显式指定为 SVG —— 单个 PNG 文件会被 electron-builder **原样按自身像素尺寸**装进 `hicolor/1024x1024/apps`，而多个发行版的 `hicolor/index.theme` 并不声明该目录（Arch 就没有），图标会解析不到；SVG 落到 `hicolor/scalable/apps`，所有发行版都声明 |
| `0004-prepare-target-electron-distribution.patch` | `prepare-dsh.ts`、`prepare-runtime.ts` | Electron 分发路径按 target 推导，不再假设「非 mac 即 win32」；打包期 `pnpm install` / 运行时冒烟改用 Host 运行时；`versions.json.node` 记为 payload 实际运行的 Node 版本；Linux 上整块跳过 rc.2 新增的 `prepare:cli`（见「注意」） |
| `0005-desktop-linux-release-settings.patch` | `desktop-package-environment.{mjs,d.mts}`、`desktop-toolchain-preflight.ts`、`.gitignore`、`.env.linux.example`、`tests/desktop-package-environment.spec.ts` | 支持 `.env.linux`；Linux 不套用 Windows/macOS 专属设置；Linux 不要求策略 origin；修掉 `win32 ? … : macOS` 的隐含假设；Linux 文件白名单加 `MAINTAINER`/`HOMEPAGE`（并从环境里剥掉，保证发布设置只由文件拥有）；打了 rpm 才预检 `rpmbuild` |
| `0006-desktop-package-linux-scripts.patch` | `apps/desktop/package.json`、`scripts/client-build-environment.ts` 与其单测、`packages/client/ui-brand-official/src/client/index.ts` 与其单测 | `package:linux:x64` / `package:linux:x64:dir`；Linux 未签名包的官方品牌（见 2026-11-03 一节） |
| `0007-tests-linux-x64-supported.patch` | 3 个 `tests/*.spec.ts` | 把「断言 Linux 抛错」改成「断言 Linux 受支持」 |

## 让 Host 跑在真 Node 上（0008–0010）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0008-desktop-host-runtime-standalone-node.patch` | `src/node-environment.ts`、`src/host-process.ts`、`src/main.ts`、`desktop-host/src/{index,cli}.ts`、`scripts/node-bin/node`、5 个 spec | 引入 `DesktopNodeRuntime`；Linux 上 Host 走 primary-runtime 的真 Node；`ELECTRON_RUN_AS_NODE` 只在真 Electron 运行时下设置；node shim 缺 `DSH_DESKTOP_NODE_EXECUTABLE` 时报错退出 78（不再静默 `exec` 空路径，那会打成 `line 6: exec: : not found` 的 exit 127）；`dsh` CLI 在「真目录树」布局下按 `resources/runtime` 找 supportDir（关掉 asar 后原来那段推导会落到 `resources/app/runtime`，见「注意」）。`desktopNodeRuntime()` 的返回值从字符串变成对象，所以 `tests/main-startup.spec.ts` 里 Host 的 `node` 断言同步改成对象 |
| `0009-desktop-packaging-host-runtime.patch` | `scripts/dev.ts`、`scripts/smoke-{runtime,prepared-runtime,packaged-runtime}.ts`、`scripts/sign-primary-runtime.ts`、`tests/fixtures/{runtime-payload-smoke,pnpm-smoke}.mjs`、`tests/prepared-runtime-smoke.spec.ts` | 把 Host 运行时贯穿 dev / 打包 / 冒烟；payload smoke 的 Electron 专属断言改为按平台判断 |
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
| `0013-desktop-linux-tray.patch` | `src/main.ts`、`src/tray.ts`、`src/background-notice.ts`、`scripts/electron-builder-config.mjs`、`scripts/render-tray-icon.ts`、`tests/main-startup.spec.ts`（只改一条断言，见 2026-11-03 一节） | 托盘的创建条件从只认 `win32` 放宽到 `win32 \|\| linux`；Linux 的托盘图是 `resources/tray-linux.png`（单张 PNG，托盘宿主自己缩放到面板；**用应用图标自身的留白，不做 Windows 那 20% 放大**，见「注意」）；首次关窗的一次性提示同样覆盖 Linux —— 它的文案本来就是「可在系统托盘中重新打开窗口」，在 Linux 上这句话只有有了托盘才成立；渲染器除 ICO 之外也输出那张 PNG；electron-builder 的 Linux `extraResources` 把它带进产物的 `resources/` |
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
（普通模式由 `0016` 打这个标记，因此完全不受影响）。

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
| `0019-desktop-linux-frameless.patch` | `src/frameless-mode.ts`（新增）、`src/wayland-csd.ts`（新增）、`src/main.ts`、`src/preload-platform.ts`、`src/preload-menu.ts`、`src/welcome-window.ts`、`src/update-overlay.ts`、`tsconfig.client.json`、`tests/{frameless-mode,main-startup,welcome-window,preload-platform.client,wayland-csd,update-overlay}.spec.ts` | `DSH_DESKTOP_FRAMELESS=1` 时主窗口加 `titleBarStyle: 'hidden'` + `titleBarOverlay`（高度 40、初始色取 `chromeFallbackFill()`），原生按钮由 Electron 自绘（见下），标题区其余部分仍由 0016 的页内 caption 提供；`windowsAppearance` 里 `setTitleBarOverlay` 的门从「只 Windows」放宽到「Windows 或 Linux 无边框」，页面实测出来的侧栏色因此也能刷到原生条上。全屏事件与 preload 的 `data-fullscreen` 监听一并放行到 Linux 无边框（全屏时原生按钮隐藏，caption 要给内容让位）。欢迎窗走同一套覆盖层（高度 42）。`preload-menu.ts` 的菜单起点改成 `max(--dsh-windows-menu-start, env(titlebar-area-x))`，系统把按钮放左侧时菜单跟着安全区右移 |

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

**已知限制**：按钮位置跟 GTK 布局走，但只有页面内菜单会避让 `env(titlebar-area-x)`；
左侧布局（用户自定义）下，侧栏顶部的切换钮仍会落在按钮下面。

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
GNOME 的桌面双击最大化还没跑（留给实机复核与三发行版矩阵）；左置按钮布局仍未验证。

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
  实测 2026-10-29（0.2.2-alpha.2）：`~/.local/share/dsh-pnpm-11/node_modules/.bin/pnpm exec vitest run
  apps/desktop/tests apps/desktop-host/tests`
  → 0 失败（182 个文件：177 通过 / 5 跳过；2115 个用例：2052 通过 / 63 跳过）。**改源码行为的补丁要在同一个补丁里改掉对应的 spec**（`0008`、
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

## 2026-11-01：linux-arm64（issue #11）

arm64 目标折进现有补丁，不新增编号；文件名保留 `-x64` 的历史名。

- `0001` / `0002` / `0006` / `0007` 的目标联合、`SUPPORTED_TARGETS`、`TARGETS`、`package.json`
  脚本与单测同时覆盖 `linux-x64` 与 `linux-arm64`。
- `package-target` 的宿主守卫由「Linux 必须 x64」改为「宿主架构 == 目标架构」：交叉构建在 prepare
  阶段就会失败（要执行目标 Electron/Node/Python），必须原生构建。
- `0009` 把 `linux-unpacked` 改成按目标架构计算：electron-builder 以 x64 为默认架构，arm64 的
  未打包目录是 `linux-arm64-unpacked`。
- PKGBUILD 的 `arch` 加 `aarch64`（只支持 Arch Linux ARM 本机 makepkg；CI 的 Arch 容器仍是 x86_64）。
- 验证（2026-11-01）：这五个补丁在干净 worktree 里按序 `git apply` 通过，与补丁态工作树逐文件
  `cmp` 零差异；`desktop-build-paths` / `desktop-auto-update-environment` / `package-target`
  三个 spec 共 48 个用例通过。

## 2026-11-03：0.2.2-alpha.3

基线 `dsh-v0.2.2-alpha.3`（`05b1cae8`）。上游这版跨 462 个提交、2315 个路径；17 个补丁里有 8 个的落点被上游动过（80 个被打补丁的文件里 14 个），12 个补丁因此重生、5 个（0003 / 0004 / 0010 / 0011 / 0012）逐字节没变。

- **`0018` 在 `AppFrame.tsx` 有三处冲突**：上游给侧栏加了窄屏抽屉（`drawer` 与 `SIDEBAR_DRAWER_BREAKPOINT`），正好压在玻璃模式的布局判断上。裁定：

  | 位置 | 裁定 |
  |---|---|
  | `collapsedWidth` | `drawer \|\| darwin \|\| linuxGlass \|\| windowsTitlebar ? 0 : SIDEBAR_COLLAPSED` |
  | leading-seat 注释 | 保留 Linux 那段说明，接在上游新注释之后 |
  | `leadingMounted` | `drawer \|\| (darwin \|\| linuxGlass) && sidebarCollapsed` |

  `SidebarRoot.tsx` 的 `drawer` 判断与 `0018` 的 `stripDesktop` 并存：玻璃模式仍然把开关放在侧栏顶部、收起后交给 frame 的 `shell.leading`。其余九个客户端文件文本合并干净。

- **`0006` 并入品牌层**（4 个文件；补丁名不变）。起因：`0006` 的 `package:linux:*` 脚本让 Linux 一律走 `--unsigned`，而上游 0.2.2-alpha.2 的 `091d6ed` 让未签名包改用 `build --profile local`，于是侧栏变成「DSH 本地构建 + 版本/提交徽标」、窗口标题也是本地构建字样。改法与边界：

  - `scripts/client-build-environment.ts`：`local` profile 的公开环境补 `DSH_CLIENT_TITLE`（复用 `OFFICIAL_CLIENT_BUILD_ENVIRONMENT` 里的常量）。local 分支本来只给 commit / version / dirty，所以光在环境变量里传 title 进不去客户端。
  - `packages/client/ui-brand-official/src/client/index.ts`：守卫从「不是 official 就返回」改成「**没有**选 profile 才返回」——未选 profile 的是纯 web 构建，仍留空。
  - **构建记录仍是 `DSH_CLIENT_BUILD_PROFILE: local`**：只改显示层，不让记录冒充 official；`pack-local-packages` 与打包记录的配对校验因此一行未动。
  - 上游两张单测同步改：`client-build-environment.client.spec.ts` 里 local 的期望加 title；`browser-plugin.client.spec.tsx` 把「profile 非 official 时槽位为空」拆成两条（local 时注册、未选 profile 时为空）。

- **`0013` 附带一处测试改动**：上游 alpha.3 新增的 `groups localized DevTools before quit` 断言「最后一次 `Menu.buildFromTemplate` 是应用菜单」，而 Linux 的托盘会在 `refreshApplicationMenu()` 里顺带重建托盘菜单，`lastCall` 于是是托盘菜单。改成取「最后一个首项带 `submenu` 的构建」，并在原地注明原因。

- **`apply-patches.sh --check` 对 `0017` 必然失败**，旧补丁同样：它逐补丁对空树试打，而 `0017` 的上下文含 `0008` 新增的行（见开头那条例外）。对应 CI 的是顺序 `git apply`，makepkg 那侧是 `patch -Np1`。

- 验证（2026-11-03）：17 个补丁在真源码包上按序 `patch -Np1` 全过，84 个触及文件与三路合并树逐字节一致；`makepkg --verifysource` 19 项通过；`build.sh --all` 一次出三格式；`verify.sh --runtime` 46 通过 / 0 失败；上游桌面单测 2115 通过 / 0 失败 / 63 跳过。

## 2026-11-04：0.2.2-rc.1（轻量同步）

基线 `dsh-v0.2.2-rc.1`（`66491b05`）。上游这版相对 alpha.3 只有 4 个提交、387 个路径 / 387 行，**全是 `package.json` 的版本行**：378 个把 `0.2.2-alpha.3` 提到 `0.2.2-rc.1`，9 个 `vendor/*/package.json` 把预发版号转正式（cordis `4.0.6-alpha.2→4.1.0`、cosmokit `1.8.7-alpha.2→1.9.0`、schemastery `3.18.6-alpha.2→3.19.0`、timer `1.1.8-alpha.2→1.2.0`，hmr / include / loader / logger-console / group 同批）。零源码改动、零依赖范围改动、零 lockfile 改动，所以 17 个补丁**逐字节零重生**。

- **唯一压在补丁落点上的变更是 `apps/desktop/package.json` 的版本行**，而它正是 `0006` 的目标文件。`0006` 的 hunk 在第 38 行、版本行在第 3 行，上下文不重叠，照旧能打。它的 `index 5d4f00e..72de86a` 仍写着 alpha.3 的 blob（新基线是 `00eee14`）——`patch` 与 `git apply` 都不读这一行，下次完整重生时会自动更新，这次刻意不动。

- **`arch` 里的 `aarch64` 这回是真的了。** 2026-11-01 那条记录写着「PKGBUILD 的 `arch` 加 `aarch64`（只支持 Arch Linux ARM 本机 makepkg）」，但 `build()` 当时写死 `package:linux:x64:dir`、`package()` 读 `targets/linux-x64`，ALARM 上根本做不出来 —— 声明与实现不一致。这一版把两处都按 makepkg 的 `$CARCH` 分支：x86_64 → `linux-x64` / `linux-unpacked`，aarch64 → `linux-arm64` / `linux-arm64-unpacked`（后者是补丁 0009 定的目录名，映射与 `scripts/verify.sh` 一致）。CI 的 arch job 也从一个变成矩阵：x86_64 用官方 `archlinux` 镜像跑在 `ubuntu-latest`，aarch64 跑在 `ubuntu-24.04-arm` 上、用社区维护的 `menci/archlinuxarm`（官方镜像只有 amd64）。两种架构都必须原生构建，交叉构建在 prepare 阶段就会去执行目标平台的 Electron / Node / Python；aarch64 的包与 arm64 的 AppImage / deb / rpm 一样，尚未在实体设备实测。

- 验证（2026-11-04）：17 个补丁在 rc.1 的 worktree 上按序 `patch -Np1` 全过（72 个文件改动 + 12 个新增）；`apply-patches.sh` 的 `git apply` 顺序应用通过（`--check` 对 `0017` 仍必然失败，原因见 11-03 那条）；`makepkg --verifysource` 19 项通过；`build.sh --all` 三格式一次出齐（`0.2.2-rc.1`）；`verify.sh --runtime` 46 通过 / 0 失败 / 4 跳过；上游桌面单测 2115 通过 / 0 失败 / 63 跳过。


## 2026-11-11：0.2.2-rc.2（完整同步）

基线 `dsh-v0.2.2-rc.2`（`ddac9676`）。相对 rc.1 是 **1568 个提交、4645 个文件、+160844 / −58399** —— 两周的上游主干，和上一版的「4 个提交全是版本号」正好是两个极端。13 个补丁的目标文件被改动，`0004` `0010` `0011` `0012` 一字未动。

- **上游把 Host 的 office 那条线整个重写了。** `apps/desktop-host/src/office-engine.ts`（48 行）与 `office.ts`（38 行）删除：`installOfficeEngineResolution()` 没了，改成 Host 入口自己把 `process.argv[4]` 记进 `process.env.DSH_PRIMARY_RUNTIME`；`runtimeArchivePath()` 搬进 `src/cli.ts`。同期 `libreoffice-kit` 0.1.5 → 0.2.3。`0008` / `0009` / `0017` 因此**重新推导而不是三路合并**：三者的 `import` 行换成新家，0017 的 `index.ts` 只剩「把 `DSH_DESKTOP_RESOURCES_PATH` 回填成 `process.resourcesPath`」这一块，替上游补 office 引擎的那部分整段删掉。

- **更新渠道改名。** `desktop-release-store.ts` 的 `channel` 从 `['nightly','latest']` 变 `['nightly','stable']`，`electron-builder-config.mjs` 与 `desktop-upload-plan.ts` 同时删掉「stable 渠道不许预发布版本」的两处守卫。`0001` / `0002` / `0003` 的 JSDoc 与上下文跟着改；Linux 不进这两条守卫，语义无变化。

- **发布设置读取被抽走。** `desktop-package-environment.mjs` 的 dotenv 读取整段移进新的 `desktop-file-settings.mjs`（`readDesktopPackageSettings`）。`0005` 从未改过那个函数本体，Linux 白名单都在常量与平台选择处，所以只重排了常量块，不搬家。

- **侧栏重构。** `SidebarRoot.tsx` +105/−70、`SidebarRoot.module.css` +168/−33、新增 `scroll-handoff.ts`（插件入口收进「更多」、插件导航与会话列表共用滚动区）；`AppFrame.module.css` +10/−26、`PluginManagerPage.module.css` +82/−14。`0018` 的玻璃模式靠类名后缀命中哈希类名，逐条复核后三个选择器仍然成立：`[class*="sidebarCol"]`（在 `AppFrame.module.css`）、`[class$="newSession"]`、`[class$="_fade"]`。

- **两个补丁新增了「上游文件」**（不在原补丁的目标列表里）：
  - `0001` 加 `apps/desktop/scripts/retain-desktop-ci.ts`：上游的发布路由（`desktop-publish-route.ts`）只认 mac/win，而我们的 target 联合多了 linux，`route.target.includes(target)` 过不了类型检查；改成 `(route.target as readonly string[]).includes(target)`，路由表本身不动。
  - `0008` 加 `apps/desktop/tests/office-resources.e2e.ts`：rc.2 新增的 e2e，构造 `DesktopHostProcess` 用的是字符串可执行文件，要改成 `DesktopNodeRuntime` 对象。

- **仓库脚本一处修正**：`scripts/verify.sh` 的客户端身份检查改从 `@deepseek-ai/dsh-deepseek-account/lib/types/client-metadata.js` 取 `platformClientHeaders` —— rc.2 起这个函数只从 `./client-metadata` 子路径导出（包根不再转出），而 tsdown 只把入口打成 `lib/index.js`，子路径落在 `lib/types/`。

- 验证（2026-11-11）：17 个补丁在 rc.2 worktree 上按序 `git apply` 与 `patch -Np1` 都全过，两条路线打出来的树与三路合并树逐字节一致；`0004`/`0010`/`0011`/`0012` 重生后与仓库原文件 `cmp` 逐字节相同；`makepkg --verifysource` 19 项通过；`build.sh --all` 三格式一次出齐（`0.2.2-rc.2`）；`verify.sh --runtime` 49 通过 / 0 失败 / 1 跳过；上游桌面单测 2348 通过 / 0 失败 / 65 跳过。

## 2026-11-13：0.2.2-rc.3（轻量同步）

基线 `dsh-v0.2.2-rc.3`（`38a6a5c9`）。相对 rc.2 仅 6 个提交（#8383 CI bubblewrap 缓存、#8385 Windows `restart-status-cwd` 修复、#8342 新增实验插件 `deepseek-chat-import`、#8397 版本号升至 `0.2.2-rc.3`）。`pnpm-lock.yaml` 有更新（+133 行），同步后须重跑 `pnpm install --frozen-lockfile`。17 个补丁中 13 个与 rc.2 逐字节一致，4 个补丁重生：

- **`0006`**：仅 `apps/desktop/package.json` 第 3 行版本号上下文偏移；`0019`：仅 `tsconfig.client.json` 索引 hash 随 #8342 新增项目引用而更新。
- **`0008`**：补齐上游 `apps/desktop/scripts/node-bin/node` 本身的 `100755` 文件模式，消除反向 `git apply` 的模式警告。
- **`0018`（含 PR #17 渐隐遮罩修复与单测补全）**：
  - `SidebarRoot.tsx` / `SidebarRoot.module.css` 与 #8342 新增的 `sidebar.session.action` 插槽及 `.newSessionRow` 无冲突三路合并；
  - 收下 PR #17 的侧栏白带修复（`Co-authored-by: stvsl`）：上游在 rc.2 侧栏重构时已将底部渐隐遮罩类名改为 `.scrollFade`，导致原 `[class$="_fade"]` 失效，现改用 `[class*="scrollFade"]`（`glass-document.ts` 与 `tests/glass-document.spec.ts`）；
  - 补全 `packages/client/ui-layout/tests/app-frame.client.spec.tsx` 中 `0018` 玻璃折叠断言遗漏的上游 `drawer: false` 字段。
- **上游仍然没有 Linux**：目标联合类型还是 `mac-arm64 | mac-x64 | win-x64`，`linux-x64` / `linux-arm64` 仍只由 `0001` / `0002` 提供。

- 验证（2026-11-13）：17 个补丁在 rc.3 worktree 上按序 `git apply` 与 `patch -Np1` 全过，13 个未受影响补丁 `cmp` 逐字节一致；`makepkg --verifysource` 19 项通过；`build.sh --all` 三格式一次出齐（AppImage `257dc787…` / deb `ebc02897…` / rpm `1de16212…`，payload 冒烟两轮全过）；`verify.sh --runtime` 49 通过 / 0 失败 / 4 跳过；去代理下上游桌面单测（`apps/desktop/tests` + `apps/desktop-host/tests`）2348 通过 / 0 失败 / 65 跳过，补丁涉及的客户端包测试（`ui-layout` / `ui-sidebar` / `ui-brand-official`）19 文件 281 用例全部通过。
