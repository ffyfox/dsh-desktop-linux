# 补丁

按文件名顺序应用（见 `scripts/apply-patches.sh`），全部相对上游 `687f282e`（tag `dsh-v0.2.1-rc.2`）。

组织约定：**一条改动只属于一个补丁**。每个补丁都是相对同一个基线的独立 diff，改动互不重复、
按编号应用（顺序依赖见下）。补丁由 `git diff -- <files>` 从开发工作树生成；**一个文件可以被
多个补丁触及**，此时必须按「基线 + 只有这一个补丁」的隔离树取 diff，否则会把另一个补丁的
hunk 一起带进来。

**`0017` 是这条约定的一个已知例外。** 它的 5 个文件（`src/node-environment.ts`、`src/main.ts`、
`tests/host-process.spec.ts`、`tests/node-environment.spec.ts`、`desktop-host/src/index.ts`）全部也属于
`0008`，而且它的 diff 上下文含 `0008` 新增的行（`resourcesPath?: string` 紧挨着 `0008` 加的
`readonly electron: boolean`），所以它单独打在干净基线上会直接 reject，只有排在 `0008` 之后才成立 ——
现有系列靠「按文件名顺序」恰好满足。重生这类补丁要走两阶段：先在「新基线 + 前置补丁」上重算，
再叠它自己的增量。

已验证（0.2.1-rc.2）：16 个补丁按序打在完整的上游 release 源码包（tag `dsh-v0.2.1-rc.2`）上，
`patch -Np1`（makepkg 的 `prepare()`）与 `git apply`（`apply-patches.sh` / CI）都干净通过（**无 fuzz、
无 reject**，只在共用文件上留 offset 与那两份 `.orig`），58 个触及文件（54 个改动 + 4 个新增），
`prepare()` 另外放置托盘 PNG；两条路打出来的这 58 个文件逐字节相同。这一轮只有 `0006` 重生（上游动了
它的基线 blob），重生结果与原版**只差 `index` 那一行**、连字节数都相同（767 B），其余 15 份逐字节未动；
offset 仍只出现在 `0013` / `0016` / `0017`，与 alpha.3 / alpha.4 / alpha.5 / rc.1 那几轮同因（系列内前置补丁
推行的行号）。`makepkg --verifysource` 的 18 条校验和逐条 `Passed`。`pnpm install --frozen-lockfile` 报
`Already up to date`，lockfile 通过供应链策略校验（1725 条、59.3 秒）—— 上游这一版没动
`pnpm-lock.yaml`，外部依赖一个也没变。
`pnpm run build:official` 的 9 道门（native addon / host compiler / Host bundle / host aggregate check /
Desktop bundle / client compiler / Client bundle / client aggregate check / Web build）**9 通过 0 失败**，
104.37 秒（比 rc.1 的 31.35 秒长得多 —— 这一版真的动了客户端代码，client compiler 重编了 325 个产物）。
上游桌面单测在补丁态下**零失败**（156 个文件：151 通过 / 5 跳过；1680 个用例：1619 通过 /
61 跳过，与 rc.1 逐项相同）。`makepkg` 整包构建成功（`dsh-desktop-linux-0.2.1rc2-1`，347 692 699 B /
28692 个文件 —— 比 rc.1 多 20 个，正是新加的两个客户端包），16 分 20 秒。`build.sh --all` 10 分 10 秒
出齐三件套：AppImage 358 869 729 B（sha256 `d9dce5f9…`）、deb 287 297 792 B（`38f0edef…`）、
rpm 238 759 519 B（`bb51af9f…`），连打包后的冒烟也过 —— payload 探针报 `koffi / sharp / html / pty /
pnpm / grep / glob` 全在场、CLI 离线装插件与卸载、`dsh web:` 起得来、Office 三种格式
（DOCX / XLSX / PPTX）转 PDF 与技能 CLI 发现。
`verify.sh` 静态 **20 通过 / 0 失败 / 14 跳过**（12 个是 alpha.3～rc.1 的旧产物按当前基线跳过，另 2 个
是「没给 `--runtime`」与「3080 没在监听」）；`verify.sh --runtime` **31 通过 / 0 失败 / 13 跳过**（同上
12 个旧产物与 3080），活体部分实测：与在跑的桌面端并存（隔离 userData），Host 在 127.0.0.1:34917 监听、
`dsh-app://` 出 UI（390 个 DOM 节点）、Host 跑在 primary-runtime 的真 Node 上、2 个渲染进程都在独立
user namespace 且 seccomp 生效、托盘注册且菜单读到 2 个带产品名的条目、`profiles/desktop` 已建立、
共享根出现工作区存储与凭据、`profiles/web` 哨兵未被触碰、真实 `~/.dsh/profiles/desktop` 未被改动。
产物里 `resources/runtime/cli` 不存在、`resources/runtime/versions.json` 记的是 primary-runtime 的
Node 24.21.0 / pnpm 11.28.5、`resources/app/dsh/package.json` 的版本是 `0.2.1-rc.2`、`desktop-runtime.json`
的 `release.version` 同样是 `0.2.1-rc.2`（vendor 包版本与 rc.1 相同，cordis 4.0.5 等）、`dshBuildCommit`
记的是上游 `687f282e…`（不是本仓库的提交），正是 0004 的 Linux 闸门、0008 的运行时选择与 0012 的
「环境变量优先」在起作用；这一版新增的 `@deepseek-ai/dsh-client-ui-deepseek-model-label-1017` 与
`@deepseek-ai/dsh-web-deepseek-api` 也确实躺在 `resources/app/dsh/node_modules` 里，跟着桌面端一起发出去。

**编号 `0014` 已作废，空号不复用。** 它当年把 lockfile 里 electron 的解析从 44.0.0 提到 44.4.5
（那个版本的 Linux 托盘在 KDE 与 GNOME 下都注册不上）；0.2.1-alpha.2 的 lockfile 自己解析到 44.7.0，
上游的 `^44.7.0` 也已经不允许 44.4.5 —— 留着不只是多余，还会让 `pnpm install --frozen-lockfile`
直接失败。所以删掉它，`0015` / `0016` 的编号保持不动：已推送的历史（`e8a3fcd` 的标题与正文）里
点名的就是 `0015`，重编号只会让发布出去的文字与工作树对不上。

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
| `0003-electron-builder-linux-configuration.patch` | `electron-builder-config.mjs` | Linux 关闭 asar；显式 `executableName`；Linux 不嵌入强制更新策略；Linux 的打包格式与包元数据来自发布设置（见 `0011`）；显式钉住 deb/rpm 的 `packageName` / `packageCategory` 与 `linux.synopsis`；用 `appImage.executableArgs: []` 去掉 legacy 工具集写死的 `--no-sandbox`；Linux 图标显式指定为 SVG —— 单个 PNG 文件会被 electron-builder **原样按自身像素尺寸**装进 `hicolor/1024x1024/apps`，而多个发行版的 `hicolor/index.theme` 并不声明该目录（Arch 就没有），图标会解析不到；SVG 落到 `hicolor/scalable/apps`，所有发行版都声明 |
| `0004-prepare-target-electron-distribution.patch` | `prepare-dsh.ts`、`prepare-runtime.ts` | Electron 分发路径按 target 推导，不再假设「非 mac 即 win32」；打包期 `pnpm install` / 运行时冒烟改用 Host 运行时；`versions.json.node` 记为 payload 实际运行的 Node 版本；Linux 上整块跳过 rc.2 新增的 `prepare:cli`（见「注意」） |
| `0005-desktop-linux-release-settings.patch` | `desktop-package-environment.{mjs,d.mts}`、`desktop-toolchain-preflight.ts`、`.gitignore`、`.env.linux.example`、`tests/desktop-package-environment.spec.ts` | 支持 `.env.linux`；Linux 不套用 Windows/macOS 专属设置；Linux 不要求策略 origin；修掉 `win32 ? … : macOS` 的隐含假设；Linux 文件白名单加 `MAINTAINER`/`HOMEPAGE`（并从环境里剥掉，保证发布设置只由文件拥有）；打了 rpm 才预检 `rpmbuild` |
| `0006-desktop-package-linux-scripts.patch` | `apps/desktop/package.json` | `package:linux:x64` / `package:linux:x64:dir` |
| `0007-tests-linux-x64-supported.patch` | 3 个 `tests/*.spec.ts` | 把「断言 Linux 抛错」改成「断言 Linux 受支持」 |

## 让 Host 跑在真 Node 上（0008–0010）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0008-desktop-host-runtime-standalone-node.patch` | `src/node-environment.ts`、`src/host-process.ts`、`src/main.ts`、`desktop-host/src/{index,cli}.ts`、`scripts/node-bin/node`、5 个 spec | 引入 `DesktopNodeRuntime`；Linux 上 Host 走 primary-runtime 的真 Node；`ELECTRON_RUN_AS_NODE` 只在真 Electron 运行时下设置；`dsh` CLI 在「真目录树」布局下按 `resources/runtime` 找 supportDir（关掉 asar 后原来那段推导会落到 `resources/app/runtime`，见「注意」）。`desktopNodeRuntime()` 的返回值从字符串变成对象，所以 `tests/main-startup.spec.ts` 里 Host 的 `node` 断言同步改成对象 |
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
| `0013-desktop-linux-tray.patch` | `src/main.ts`、`src/tray.ts`、`src/background-notice.ts`、`scripts/electron-builder-config.mjs`、`scripts/render-tray-icon.ts` | 托盘的创建条件从只认 `win32` 放宽到 `win32 \|\| linux`；Linux 的托盘图是 `resources/tray-linux.png`（单张 PNG，托盘宿主自己缩放到面板；**用应用图标自身的留白，不做 Windows 那 20% 放大**，见「注意」）；首次关窗的一次性提示同样覆盖 Linux —— 它的文案本来就是「可在系统托盘中重新打开窗口」，在 Linux 上这句话只有有了托盘才成立；渲染器除 ICO 之外也输出那张 PNG；electron-builder 的 Linux `extraResources` 把它带进产物的 `resources/` |
托盘 PNG 是二进制，`patches/` 装不下：makepkg 用的是 GNU patch，它不支持 git 的二进制补丁。
所以这张图作为普通本地 `source` 走，仓库里存在 `assets/tray-linux.png`，由两条路径各自放进
`apps/desktop/resources/`：PKGBUILD 的 `prepare()`（`makepkg` 路线）和 `scripts/apply-patches.sh`
（CI 与本地 `build.sh` 路线）。刷新它 = 在 `apps/desktop` 里跑 `pnpm run render:tray-icon`，
再把输出的 `resources/tray-linux.png` 拷进 `assets/`（图和 Windows 托盘同源，都是
`resources/icon-windows.svg`）。

## 让关窗提示在 Wayland 下真的显示出来（0015）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0015-desktop-linux-hidden-overlay-reveal.patch` | `src/update-overlay.ts`、`tests/update-overlay.spec.ts` | 提示浮层是 `transparent: true` + `show: false` 的子窗口，只在 `ready-to-show` 里 `show()`；而这种窗口在 Wayland 下不报告首帧，于是浮层建好了、内容也渲染对了，却始终 `isVisible() === false` —— 用户既看不到也点不到，关窗看起来像卡住。Linux 上再用 `did-finish-load` 兜一次 `reveal()`；Windows/macOS 的 `ready-to-show` 行为一字未动。测试里那个假窗口的 `webContents` 补上 `once()`，否则 Linux 分支一调就抛 |

`0015` 是 `0013` 的下游：Linux 的首次关窗提示是 `0013` 打开的，而它用的正是这个浮层。

## 让 Linux 的标题栏与 Windows 一致（0016）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0016-desktop-linux-caption.patch` | `src/main.ts`、`src/preload-windows.ts`、`src/welcome-window.ts`、`tests/{main-startup,welcome-startup,welcome-window,preload-windows.client}.spec.ts` | Linux 借用 Windows 的 caption：`createWindow()` 里对 Linux 关掉原生菜单栏（`setMenuBarVisibility(false)`，application menu 仍挂着，所以菜单项与加速键都还在）；preload 的平台门从只认 `win32` 放宽到 `win32 \|\| linux`，页面因此拿到 `data-windows-titlebar` 并挂上「应用 / 编辑」两个自绘菜单按钮。这两个按钮点开的是原生弹窗，走 Windows 那条 `DESKTOP_IPC.windowsMenu`，所以那个 IPC 块与右键菜单的角色标签也一起放宽到 Linux —— 角色项（`undo` / `copy` / `selectAll` …）因此改用 DSH 字典里的标签，不再回落 Electron 内置的英文角色名。`windowsAppearance` 这个 handler 里真正碰 Electron API 的那一句（`setTitleBarOverlay`）**仍只归 Windows**：窗口的 `titleBarOverlay` 只在 `win32 && primary` 时创建，Linux 上调它必抛异常（见「注意」），所以只放宽菜单与语言同步，不放宽 overlay 上色。未登录的欢迎窗是另一条 `new BrowserWindow()` 路径（`welcome-window.ts`），那个窗口里没有页面内 caption 条，Linux 的原生菜单栏会在标题栏下面独自占一条，所以也一并关掉。测试上：Linux 分支会调 `setMenuBarVisibility()`，三处假窗口替身补上这个方法（`main-startup.spec.ts` 里那 5 个 Linux 用例原本会因此卡到 5 秒超时）；`preload-windows.client.spec.ts` 里「Linux 上不装 Windows 控件」的断言换成「Linux 装 caption 并上报取色」 |

这是**半统一**：窗口装饰一律不动（KDE 是 KWin 的装饰插件、GNOME 是 Mutter 画的、平铺窗口管理器
本来就没有装饰），只把网页内那一条 caption 对齐 Windows。Linux 的 in-page 菜单与 Windows 共用
同一套属性与度量（`data-windows-titlebar`、`--dsh-windows-titlebar-height: 40px`、
`--dsh-windows-menu-start`，见 `preload-menu.ts`），所以客户端一个字都没改。

## 让插件市场认得宿主版本（0017）

| 补丁 | 覆盖文件 | 内容 |
|---|---|---|
| `0017-desktop-host-resources-path.patch` | `src/node-environment.ts`、`src/main.ts`、`desktop-host/src/index.ts`、2 个 spec | Linux 的 Host 跑在 primary-runtime 的真 Node 上（0008），进程里没有 Electron 的 `process.resourcesPath`，dsh-market 的宿主探测（`dshHostInfo()`，靠它认出 `resources/app/dsh/node_modules/@deepseek-ai/dsh`）两路全落空 → 市场全程「宿主版本未知」。现在 shell 把打包安装的 resources 根随 `DesktopNodeRuntime.resourcesPath` 交给 Host（`desktopNodeEnvironment()` 只对 standalone 运行时展开成 `DSH_DESKTOP_RESOURCES_PATH`），Host 入口在 Electron 之外把它回填成 `process.resourcesPath` —— dsh-market 的 Electron 探测分支原样命中，#778 的嵌套候选天然覆盖本布局。Electron 运行时一字未动：它自带真值，且子进程里的值永远优先 |

`0017` 的每个文件也属于 `0008`，且它的 diff 上下文含 `0008` 新增的行，所以**只有排在 `0008` 之后才成立**
（见开头那条例外）。

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
  实测 2026-10-17（rc.2）：`/home/firefly/.local/share/dsh-pnpm-11/node_modules/.bin/pnpm exec vitest run
  apps/desktop/tests apps/desktop-host/tests`
  → 0 失败（156 个文件：151 通过 / 5 跳过；1680 个用例：1619 通过 / 61 跳过）。**改源码行为的补丁要在同一个补丁里改掉对应的 spec**（`0008`、`0015`、
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
- **`0015` 的根因是量出来的，不是猜的。** 用 `--remote-debugging-port=9222 --inspect=9229` 起应用，
  从主进程读 `BrowserWindow.getAllWindows()`：关窗后浮层窗口存在、`modal: true`、内容与按钮位置都对，
  但 `isVisible()` 是 `false`；手动 `show()` 一次即正常显示且可用鼠标点。Debian 13（GNOME 48.7）与
  Ubuntu 26.04（GNOME 50.1）都如此，打上 `0015` 后两边都变成 `true`，鼠标点 Confirm 能写入 marker 并隐藏窗口。
  整个桌面端只有这一个窗口依赖 `ready-to-show`，所以只修这一处。
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
