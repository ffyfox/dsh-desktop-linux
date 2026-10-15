# dsh-desktop-linux

**中文** | [English](README.en.md)

> 本项目为独立社区项目。**不是** DeepSeek 官方产品，与 DeepSeek 无隶属关系。

把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 官方桌面端
（`apps/desktop` 的 Electron 应用）的**打包流水线**移植到 Linux，产出
AppImage / deb / rpm / Arch 包。

上游目前明确不支持 Linux（`apps/desktop/README.md`：*"Linux is not a supported Desktop
release target."*）。本项目补的就是这一块：让官方打包流水线认得 `linux-x64` 并产出安装包。
当前验证范围见[验证状态](#验证状态)。

![DeepSeek Harness 桌面端界面](docs/screenshot.png)

## 项目产物

本项目的产物是**官方 Electron 应用本身**：

- 渲染走自己的 `dsh-app://` 协议，而不是去连一个本地 Web 服务；
- 内置 Node / pnpm / Python 运行时，不依赖系统 Node；
- 独占 `$DSH_HOME/profiles/desktop`，不占用 `web` profile。

代价是构建重得多：要拉上游 monorepo、跑 pnpm workspace 构建、再用 electron-builder 打包。

## 安装

可从 [Releases](https://github.com/ffyfox/dsh-desktop-linux/releases) 下载 AppImage / deb / rpm 产物。

| 发行版 | 格式 | 安装方式 |
|---|---|---|
| 通用 | AppImage | `chmod +x` 后直接运行 |
| Debian / Ubuntu | deb | `sudo apt install ./deepseek-harness-*.deb` |
| Fedora / RHEL | rpm | `sudo dnf install ./deepseek-harness-*.rpm` |
| Arch Linux | PKGBUILD | 仓库自带，本地 `makepkg` 构建（未发布到 AUR），见 [Arch 包](#arch-包) |

产物是 **unsigned** 构建（文件名里带 `-unsigned`）。安装后 `dsh://` 链接会交给它处理。

## 从源码构建

依赖：Node 22.19+ 或 24+（**别用发行版打包的 Node 22**，见下）、**pnpm 11**、git。
打 rpm 还需要系统有 `rpmbuild`。

```bash
git clone https://github.com/ffyfox/dsh-desktop-linux
cd dsh-desktop-linux

./scripts/fetch-upstream.sh      # 拉上游源码（默认用 PKGBUILD 里钉的 tag）
./scripts/apply-patches.sh       # 打补丁
./scripts/build.sh --all         # AppImage + deb + rpm
./scripts/verify.sh --runtime    # 验证矩阵
```

`build.sh` 的参数：`--dir`（只出未打包目录，最快）、`--appimage`（默认）、`--deb`、`--rpm`、`--all`。
整条流水线（`build:official` → `release:pack` → `prepare:*` → `package`）才是耗时大头，
多打一种格式只多一次 fpm/AppImage 打包，所以分开跑更快，也更容易定位失败。

产物落在 `upstream/apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/`。

deb / rpm 的 `Maintainer:` / `Homepage:` 来自 `upstream/apps/desktop/.env.linux`。`build.sh`
首次运行就从仓库里的 `.env.linux.example` 生成，值已经填好。要换成你自己的，改那个文件即可：
**同名环境变量会被上游整个滤掉**，`DSH_DESKTOP_LINUX_MAINTAINER=… build.sh --deb` 静默无效。

### 硬性前提

**Node 要带 TypeScript 类型剥离。** nodejs.org 的官方包 22.19+ / 24+ 都有，但**发行版自己打的可能没有**
（Ubuntu 26.04.1 的 `nodejs 22.22.1` 实测 `process.features.typescript` 为 `false`，加
`--experimental-strip-types` 也仍是 `false`），构建会在第一步 `build:official` 报
`build: Node.js TypeScript type stripping is unavailable`。用官方 Node（我们 CI 钉的是 Node 24）。

**必须用 pnpm 11，而且要是 npm 或 corepack 装的那种。** 上游仓库声明
`packageManager: pnpm@11.28.5`，pnpm 11 会自己切到该版本；pnpm 9 会在 `pnpm install` 报
`ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`。官方 standalone 安装器与 Homebrew 给的是编译好的二进制，
上游三处脚本会 `node $npm_execpath` 而报 `SyntaxError`；`build.sh` 碰到这种会退到隔离版并说明。

**PKGBUILD 做同一套检查。** 它在 `build()` 里内联了同样的入口探测：系统 pnpm 不是 11.x、或它
交给脚本的入口不能被 node 执行时，退到隔离版 `~/.local/share/dsh-pnpm-11`；两者都不可用则打印
安装命令后停下，而不是以 `SyntaxError` 的形式炸在打包流水线中途。

## Arch 包

PKGBUILD 直接吃上游的 release 源码包，不依赖 `./upstream` 检出：

```bash
./scripts/pkgbuild-dir.sh     # 摊平成 ./pkgbuild
cd pkgbuild && makepkg -si
```

本项目不发布到 AUR，PKGBUILD 只用于本地构建。

Arch 包只出未打包目录装进 `/opt/deepseek-harness-desktop`，`/usr/bin/deepseek-harness` 是符号链接。

## 它是怎么工作的

```
官方 Electron 壳（apps/desktop）
├── 渲染进程 ──── dsh-app:// 协议 ──── 应用 UI
└── Host 进程 ─── primary-runtime 自带的真 Node ─── 捆绑的 dsh 运行时
                       └── $DSH_HOME/profiles/desktop
```

三个值得知道的设计点：

- **Host 跑在真 Node 上，不是 Electron 的 node 模式。** Electron 的 node 模式下 `sharp` 解码会段错误，
  所以 Linux 的 Host 改走 primary-runtime 自带的 Node。连带地，**Linux 产物的 dsh 目录树不放进 asar**
  （真 Node 读不了归档），这是 `linux-unpacked` 体积偏大的原因。
- **profile 是独占的。** 桌面端用 `$DSH_HOME/profiles/desktop`，CLI 连参数层面都拒绝这个 profile
  （`error: profile "desktop" is managed exclusively by the Electron application`）。
  会话、设置、凭据仍在 `$DSH_HOME` 根上，与 CLI 共享。想复用 web 的配置就做一次性迁移：退出桌面端后把
  `$DSH_HOME/profiles/web` 复制或改名过去，之后两边各自演化；用符号链接共用同一份目录实测可行，但两边会
  互相改写，桌面端的启动恢复动作也会作用到这份共享目录，两边版本跨度较大时可能出现未知问题。
- **沙箱。** 内核支持非特权 user namespace 时走 namespace 沙箱（渲染进程在独立 user namespace + seccomp）；
  不支持才退回 setuid `chrome-sandbox`。AppImage 交给 AppRun 自己探测，deb / rpm / Arch 包在
  postinst 里做同样的判断。

### 关窗、托盘与退出

**关窗不会完全退出程序——这是上游的设计。** 上游 `main.ts` 拦截主窗口的 `close`
并改为**隐藏**：Host 继续跑、正在跑的任务不中断，会话写锁也不释放。

上游没有给 Linux 准备 **「回到隐藏窗口」** 或 **「完全退出程序」** 的路径。
参考上游在其他平台的实现，补丁 `0013` 把托盘补上：图标常驻，带托盘菜单。

- 找回窗口：托盘菜单「打开」，或再启动一次（第二次启动只聚焦已有实例）。
- 完全退出：托盘菜单「退出」、菜单栏 `Application` → `Quit`、或 `Ctrl+Q`。

### 插件市场的宿主版本

设置 → 插件市场里能正常读到宿主版本（「宿主版本未知」已由补丁 `0017` 修复）：Linux 的
Host 进程是独立 Node（见补丁 `0008`），没有 Electron 的 `process.resourcesPath`，
dsh-market 的宿主探测会落空；`0017` 把打包安装的 resources 根传给 Host 并回填，
探测恢复，兼容性筛选与「更新到兼容版本」随之可用。

## 验证状态

**当前实测环境较少，后续会尽可能拓展。** 下面两张表随反馈更新——欢迎在
[Issues](https://github.com/ffyfox/dsh-desktop-linux/issues) 报告你的结果，能用和不能用
都欢迎。

### 环境

| 环境 | 状态 |
|---|---|
| Arch Linux · KDE Plasma 6 · Wayland · x86_64 | **已实测**，正常 |
| Ubuntu 26.04 LTS · GNOME 50 · Wayland · x86_64 | **已实测**，正常（托盘宿主 Ubuntu 自带） |
| Debian 13 · GNOME 48 · Wayland · x86_64 | **已实测**，正常（托盘要装扩展，见[已知限制](#已知限制)） |
| Fedora 44 Workstation · GNOME 50 · Wayland · x86_64 | **已实测**，正常（托盘要装扩展，见[已知限制](#已知限制)） |
| 其他发行版（Linux Mint / CachyOS 等） | 未验证 |
| 其他DE/WM（Xfce / Hyprland 等） | 未验证 |
| X11 | 未验证 |
| aarch64 | 未构建、未验证 |

### 产物

| 产物 | 状态 |
|---|---|
| AppImage | **已实测**：`chmod +x` → 启动 → 托盘、关窗 → 退出 |
| deb | **已实测**：`apt install` → 启动 → 托盘、关窗 → 退出 |
| rpm | **已实测**：`dnf install` → 启动 → 托盘、关窗 → 退出 |
| Arch 包 | **已实测**：`makepkg` → `pacman -U` 安装 → 启动、沙箱、卸载 |
| `linux-unpacked` | **已实测**：`verify.sh --runtime` 活体矩阵 |

## 已知限制

- **GNOME 默认看不到托盘，要自己装扩展。** 托盘走 freedesktop 的 StatusNotifierItem，GNOME 本体
  不提供宿主，装 `gnome-shell-extension-appindicator` 才有（Ubuntu 默认已装；Debian 要自己
  `apt install`，Fedora 要 `dnf install`）。装完还有两个坑：扩展 UUID 是
  `ubuntu-appindicators@ubuntu.com`（Debian 13 的 59-4 就是这个名字，旧文档里的
  `appindicatorsupport@rgcjonas.gmail.com` 已废弃），而且**新装的
  扩展不会热加载**，得注销重登才生效。没有托盘宿主时图标不会出现，关窗后就只能靠二次
  启动把窗口找回。
- **AppImage 要系统提供 FUSE 2（`libfuse.so.2`）。** 主流发行版现在默认只装 FUSE 3（Debian 13、
  Ubuntu 26.04、Fedora 44 实测都只有 `libfuse3.so.3`），直接运行会报
  `dlopen(): error loading libfuse.so.2`。装对应包即可：Fedora `sudo dnf install fuse-libs`、
  Debian 13 与 Ubuntu 24.04+ `sudo apt install libfuse2t64`（Ubuntu 22.04 是 `libfuse2`）；
  或 `APPIMAGE_EXTRACT_AND_RUN=1 ./deepseek-harness-*.AppImage` 绕过（解包到 /tmp，多占约 1.2 G）。
  deb / rpm / Arch 包不受影响。
- **没有自动更新。** 上游的强制更新策略通道只认 `desktop-win` / `desktop-mac` 客户端身份，
  Linux 产物也没有更新通道，所以 Linux 版不嵌入策略、不轮询、不会自己更新。
- **没有「安装命令行工具」入口。** 官方桌面端在 macOS / Windows 上能从菜单把自带的 `dsh` CLI 装进
  PATH（macOS 提权建 `/usr/local/bin/dsh` 符号链接，Windows 写用户 PATH）；上游只实现了这两条分支，
  Linux 产物不提供。想在终端用 `dsh` 得自己装，或直接用应用自带的那份
  （`resources/app/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js`，配 `resources/runtime/primary-runtime`
  里的 node）。
- **不签名。** 产物是 unsigned 构建。
- **Platform 侧会把 Linux 客户端认成 macOS。** 上游的客户端身份映射是
  `platform === 'win32' ? 'desktop-win' : 'desktop-mac'`，Linux 落到 `desktop-mac`。
  这是上游类型联合 `'darwin' | 'win32' | null` 的结果，不是本项目引入的；
  同一个请求里的 `device_model` 又是 `linux-x64`。
- **`linux-unpacked` 约 1.1G。** asar 关闭后是小文件目录树，AppImage 压成 squashfs 后 339M，
  但首次启动的文件读取比 asar 多。
- **只做 x86_64。**

## 许可

MIT
