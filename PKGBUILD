# Maintainer: ffyfox <299493445+ffyfox@users.noreply.github.com>
#
# 官方 DeepSeek Harness 桌面端（Linux），从上游 monorepo 的 release 源码包构建。
# 这不是社区套壳版：跑的就是上游 apps/desktop 的 Electron 打包流水线。
#
# 本目录里的 *.patch 是补丁系列（见 patches/README.md）。它们必须平铺在 PKGBUILD 旁边：
# makepkg 只在 PKGBUILD 所在目录里按 basename 找本地 source，放进 patches/ 子目录会直接报
# "<file> was not found in the build directory and is not a URL"（实测）。用
# scripts/pkgbuild-dir.sh 从仓库根目录生成这个平铺目录。
#
# 注意：namcap 的 invalidstartdir 规则会连注释一起扫，所以上面刻意用「PKGBUILD 所在目录」
# 而不是 makepkg 那个起始目录变量名——写了字面量就会被报成 "File referenced in ..."，
# 让 namcap 出假阳性。精确写法见 scripts/pkgbuild-dir.sh 的注释。
#
# 硬性前提：pnpm >= 11。仓库声明 packageManager: pnpm@11.28.5，pnpm 11 会自己切到该版本；
# pnpm 9 会报 ERR_PNPM_LOCKFILE_CONFIG_MISMATCH。

pkgname=dsh-desktop-linux
pkgver=0.2.1rc2
pkgrel=1
_tag='dsh-v0.2.1-rc.2'
_commit='687f282e8625c6b8d11ff58211a90524be2e4317'
# GitHub 源码包的顶层目录名 = <repo>-<tag>，tag 自带的 "v" 不剥（实测 dsh-v0.2.1-alpha.2）
_srcdirname="deepseek-harness-$_tag"

pkgdesc='Official DeepSeek Harness desktop application (Electron shell around a bundled dsh runtime)'
arch=('x86_64')
url='https://github.com/ffyfox/dsh-desktop-linux'
license=('MIT')
# 上游 deb/rpm 的 control 里声明的运行时依赖，换成 Arch 的包名，再加上 ldd 显示而
# Debian 那边由传递依赖带来的 alsa-lib / dbus。剩下的（cairo、pango、libx11、libcups、
# libgbm、libxkbcommon、at-spi2-core、libepoxy、wayland …）都由 gtk3 拉进来——实测
# `pactree -u gtk3` 含 mesa，包级别 namcap 对这些一条也没报。
# libxcrypt-compat 是唯一落在 gtk3 闭包外的：捆绑 Python 里那个已废弃的 _crypt 模块链接
# libcrypt.so.1，而 glibc 2.38 之后这个 soname 由 libxcrypt-compat 提供。namcap 会报它。
# libdbusmenu-glib 同理是 namcap 看不见的一项，但成因不同：它不是 ELF 依赖而是 dlopen 的。
# Electron 的 Linux 托盘走进程内 StatusNotifierItem（二进制里没有 appindicator 字样，
# ldd/NEEDED 里也没有），图标本身不需要 libappindicator；但托盘菜单要靠
# libdbusmenu-glib.so.4 才能导出（二进制里有这个库名和 dbusmenu_* 符号名，却不在 NEEDED 里）。
# 缺了它，托盘图标还在、右键菜单是空的——等于没有退出入口。
depends=('gtk3' 'nss' 'libnotify' 'libxss' 'libxtst' 'xdg-utils' 'at-spi2-core'
         'libsecret' 'alsa-lib' 'dbus' 'libxcrypt-compat' 'libdbusmenu-glib')
# python 是 node-gyp 的后备：正常情况下 node-pty / sharp / koffi / native-system 都命中预编译
# 产物（实测这次构建没有编译任何东西），但预编译缺失时 pnpm install 会退回源码编译。
# 其余构建工具（patch、bsdtar、make、gcc）由 makepkg 假定存在的 base-devel 提供。
makedepends=('nodejs' 'pnpm' 'python')
# 与 AUR 上同上游的 deepseek-harness-desktop 撞一个文件：
# /usr/share/icons/hicolor/scalable/apps/deepseek-harness.svg。pacman 遇到同名文件会直接拒装，
# 声明冲突让它先提示卸掉对方；本机从旧包名升上来也走这条路。
conflicts=('deepseek-harness-desktop')
options=('!strip' '!debug' '!emptydirs')
install="$pkgname.install"

source=("$pkgname-$pkgver.tar.gz::https://github.com/deepseek-ai/deepseek-harness/archive/refs/tags/$_tag.tar.gz"
        # 补丁必须平铺（见文件头说明），顺序即文件名顺序
        '0001-desktop-target-model-add-linux-x64.patch'
        '0002-package-target-add-linux-x64.patch'
        '0003-electron-builder-linux-configuration.patch'
        '0004-prepare-target-electron-distribution.patch'
        '0005-desktop-linux-release-settings.patch'
        '0006-desktop-package-linux-scripts.patch'
        '0007-tests-linux-x64-supported.patch'
        '0008-desktop-host-runtime-standalone-node.patch'
        '0009-desktop-packaging-host-runtime.patch'
        '0010-desktop-linux-policy-opt-out.patch'
        '0011-desktop-linux-package-metadata.patch'
        '0012-desktop-build-commit-release-archive.patch'
        '0013-desktop-linux-tray.patch'
        '0015-desktop-linux-hidden-overlay-reveal.patch'
        '0016-desktop-linux-caption.patch'
        '0017-desktop-host-resources-path.patch'
        # 补丁系列是文本 diff，装不下托盘 PNG —— GNU patch（makepkg 与 PKGBUILD 都用它）
        # 不支持 git 的二进制补丁。所以这张图作为普通本地 source 平铺过来，由 prepare() 放进源码树。
        'tray-linux.png')
sha256sums=('dec9f36f9b25028ca8de2a7520e16029ad36e8328078fb33b85b1b9b338d5690'
            'f201c9826fa2ab835b335785dc01063a3c173de29768e6ef253654d75dae1b42'
            '2c551d85a71e27599d70a5f2dd36ce5536f28f113f2e9dd7145803abc4512356'
            '67e1f95510ffb8f058365a6691561580e5c0874684d95bdbe968f9d8ab37bf6c'
            '0d47d53b952a3e5e7a1e68e5db89199a2bc550f34867f30fef0867a96c79ace7'
            'a70e694d28806f416e066e44571f03039ed433553648bcab582f95d4e788d03e'
            '0d39845c9252adfe2d2702cb0274c2d505ee0114db7535e24eedcdc609fdb429'
            '25e433508b7c4c1ef48ec60b26ef2c5dd3a5f6bfe479d71f474fe1d0721af768'
            'f42d4a7506837e73c2b01ad912873654fe7797fa6373f1c5f3352911d11f6504'
            '006f028f9970922bb998e76a90d5f0e0d6ce885e95eeaccc69da9762cd9d4efb'
            'e1c9243ca4c39b22db972d4b848671e7f5e0e77485c578c7ced3dbea83c2867b'
            'a3ff4a524a4ebe28551797bd36dab7b7139516e668462f054e616e8a521e3e8f'
            '2a48cc7e75591f89e5e26606b4ce34b6e00db4891c4725ec171287af1f84fc50'
            '8ba2af41630bae288f995d93eee8252c152ffa2087bf584f3479f7ef8578f695'
            '88f5c12d7a6257c8f56f0b7cfe4171b47c90aae8818f36549ee9d5bfcf7a3867'
            '58100d6a91dbb969b32602d2db2f24422c4dbc356a84e2c6150bb2c0667afca0'
            'fc071d3ab47457e81ffb44b45460f92b8f4744ebe10b678fe5edd70923395061'
            'd1153ab7bb1c61ca7f6568b4525f6c3f3c7bf9a9e29af1697f3c02da7dee5322')

prepare() {
  cd "$srcdir"

  # makepkg 只在成功后才清 $srcdir。失败重跑时它会重新解包源码包，把补丁改过的文件恢复
  # 原状，却留下补丁新增的文件（0005 的 .env.linux.example）—— 于是 0005 变成「一半已
  # 应用」，正向反向都打不上。直接从源码包重建工作树，prepare() 就可以反复执行。
  rm -rf "$_srcdirname"
  bsdtar -xf "$srcdir/$pkgname-$pkgver.tar.gz" -C "$srcdir"
  cd "$_srcdirname"

  # 全部补丁都相对同一个基线（$_tag）生成，互相独立，按文件名顺序应用即可。
  local patchfile
  for patchfile in "${source[@]}"; do
    [[ "$patchfile" == *.patch ]] || continue
    msg2 "applying $(basename "$patchfile")"
    patch -Np1 -i "$srcdir/$(basename "$patchfile")" || return 1
  done

  # 托盘 PNG 落进上游的资源目录（为什么不做成补丁见 source 里的说明）。补丁 0013 让 Linux 的
  # 托盘指向 resources/tray-linux.png，electron-builder 再把它拷进产物的 resources/。
  # 这张图由上游自己的渲染器生成：apps/desktop 里跑 `pnpm run render:tray-icon`（补丁 0013
  # 让该脚本除了 ICO 之外也输出这张 PNG），然后拷进仓库的 assets/。
  install -Dm644 "$srcdir/tray-linux.png" apps/desktop/resources/tray-linux.png
}

build() {
  cd "$_srcdirname"

  # 上游三处脚本是无条件 `node $npm_execpath` 复起 pnpm（package-target.ts / flock-entry.ts /
  # dev.ts），所以「它交给脚本的入口能不能被 node 执行」是硬前提。
  #
  # 光把 /usr/bin 钉在 PATH 最前**拦不住**：pnpm 的版本自管理在「运行版本 ≠ packageManager
  # 声明版本」时会在 pnpm 内部把入口换成自己取的副本，pnpm 12 取的是 @pnpm/exe（ELF），
  # node 加载它直接 SyntaxError —— 2026-10-15 的 CI arch job 就是这样挂的（容器里 pacman
  # 装到 pnpm 12，自管理切到 store 里的 @pnpm/exe）。所以下面不只看版本，还要探一次入口，
  # 探不过就退到隔离版（npm 装的 11.28.5，与声明版本一致、不会自管理，入口是 JS）。
  # 探法与 scripts/select-pnpm.sh 同源 —— 那份给 build.sh / dev-desktop.sh 用，而 pkgbuild/
  # 摊平目录里没有 scripts/，所以这里只能内联一份。
  export PATH="/usr/bin:$PATH"

  # 隔离的 dsh 数据目录：构建期 Host 会往这里写东西，绝不能落到用户真实的 ~/.dsh。
  export DSH_HOME="$srcdir/dsh-home"

  # 上游平时从 git checkout 读这两个值（scripts/client-build-environment.ts 的
  # repositoryCommitHash、apps/desktop/scripts/desktop-build-commit.mjs 的
  # readDesktopBuildCommit）。release 源码包里没有 .git，所以显式给出；补丁 0012 让环境里
  # 记下的这一对优先于 git —— 否则 makepkg 的 $srcdir 落在本仓库工作树里，探针会成功，
  # 把本仓库的 HEAD 当成上游提交记进产物。dirty=1 是事实：这个构建确实打了补丁。
  export DSH_CLIENT_COMMIT_HASH="$_commit"
  export DSH_DESKTOP_BUILD_COMMIT="$_commit"
  export DSH_DESKTOP_BUILD_DIRTY=1

  # --- 挑一个合用的 pnpm：版本 11.x + 入口能被 node 执行（两条缺一不可）---

  # 复刻上游那三处的调用方式：在钉了同一个 packageManager 的临时工程里跑一个脚本，让脚本
  # 自己执行 `node $npm_execpath --version`（上游就是这么炸的）。
  _dsh_pnpm_entry_runs_under_node() {
    local probe rc=0
    probe="$(mktemp -d)"
    cat > "$probe/package.json" <<'JSON'
{ "name": "pnpm-entry-probe", "private": true, "packageManager": "pnpm@11.28.5",
  "scripts": { "probe": "node probe.cjs" } }
JSON
    cat > "$probe/probe.cjs" <<'JS'
require('node:child_process').execFileSync(process.execPath, [process.env.npm_execpath, '--version'], { stdio: 'ignore' })
JS
    ( cd "$probe" && "$1" run --silent probe >/dev/null 2>&1 ) || rc=$?
    rm -rf "$probe"
    return "$rc"
  }

  _dsh_pnpm_usable() {
    [[ -n "${1:-}" && -x "$1" ]] || return 1
    [[ "$("$1" --version 2>/dev/null)" == 11.* ]] || return 1
    _dsh_pnpm_entry_runs_under_node "$1"
  }

  local PNPM _pnpm_why="" _pnpm_version
  PNPM="$(command -v pnpm || true)"
  if [[ -z "$PNPM" ]]; then
    _pnpm_why="系统里没有 pnpm"
  else
    _pnpm_version="$("$PNPM" --version 2>/dev/null || true)"
    if [[ "$_pnpm_version" != 11.* ]]; then
      _pnpm_why="版本不是 11.x（${_pnpm_version:-取不到版本}）—— 上游声明 packageManager: pnpm@11.28.5，pnpm 9 会报 ERR_PNPM_LOCKFILE_CONFIG_MISMATCH，pnpm 12 会自管理换入口"
    elif ! _dsh_pnpm_entry_runs_under_node "$PNPM"; then
      _pnpm_why="它交给脚本的入口不能被 node 执行（自管理换成了 @pnpm/exe 之类的二进制）"
    fi
  fi

  if [[ -n "$_pnpm_why" ]]; then
    local _pnpm_fallback="$HOME/.local/share/dsh-pnpm-11/node_modules/.bin/pnpm"
    if _dsh_pnpm_usable "$_pnpm_fallback"; then
      PNPM="$_pnpm_fallback"
      msg2 "系统的 pnpm 不合用（$_pnpm_why），改用隔离版：$PNPM ($("$PNPM" --version))"
    else
      error "系统的 pnpm 不合用：$_pnpm_why"
      error "装一个隔离版后重试（需要 npm；Arch 上 npm 是独立包）：npm i --prefix ~/.local/share/dsh-pnpm-11 pnpm@11.28.5"
      return 1
    fi
  fi

  # Linux 发布设置：APP_ID 必填。MAINTAINER/HOMEPAGE 只在打 deb/rpm 时要（fpm 的 control
  # 缺这两项会拒收），本包只出未打包目录，所以不需要。
  # 强制更新策略通道是 Windows/macOS 专有的：Linux 产物没有更新通道，所以不嵌入策略、不轮询，
  # 上游要求必填的 *_ORIGIN 在这里用不到。
  cat > apps/desktop/.env.linux <<EOF
DSH_DESKTOP_APP_ID=com.deepseek.harness
EOF

  # 发布设置只能来自文件（环境里的同名变量会被 desktop-package-environment 剥掉），所以要让
  # 构建期内部的 pnpm 走镜像源、必须写进 .env.linux。打包者用环境变量传入，不传则保持上游默认
  # （registry.npmjs.org —— 本机实测单条请求要 30–40 秒，payload 安装会直接超时失败）：
  #   DSH_DESKTOP_NPM_REGISTRY=https://registry.npmmirror.com makepkg -C -s --nocheck
  if [[ -n "${DSH_DESKTOP_NPM_REGISTRY:-}" ]]; then
    printf 'DSH_DESKTOP_NPM_REGISTRY=%s\n' "$DSH_DESKTOP_NPM_REGISTRY" >> apps/desktop/.env.linux
  fi

  "$PNPM" install --frozen-lockfile

  # 可选：复用一份已有的打包流水线下载缓存。流水线自己的缓存是树内的
  # apps/desktop/.desktop-build/downloads/（键 = 资产内容的 sha256，Electron 那条是下载 URL 的
  # sha256），而 makepkg 每次从源码包重建这棵树，所以默认每次都要重下 Electron（~117MB）与
  # primary-runtime 的 Node/Python/wheels（~110MB）。指向一份已有的 downloads 目录即可跳过：
  #   DSH_DESKTOP_LINUX_DOWNLOAD_CACHE=/path/to/.desktop-build/downloads makepkg -C -s --nocheck
  # 不设这个变量时行为完全不变；设了也只是 cp -n，绝不覆盖已有文件。
  if [[ -n "${DSH_DESKTOP_LINUX_DOWNLOAD_CACHE:-}" ]]; then
    install -d apps/desktop/.desktop-build/downloads
    cp -an "$DSH_DESKTOP_LINUX_DOWNLOAD_CACHE/." apps/desktop/.desktop-build/downloads/
  fi

  # Electron 二进制（~117MB）平时由 require('electron') 首次自动下载到 ~/.cache/electron。
  # 这里显式预热一次，让下载失败发生在构建前，而不是打包流水线中途。
  #
  # 注意：@electron/get 即使在缓存命中时也会回源拉同源的 SHASUMS256.txt 校验，所以要打到
  # GitHub releases 的网络不通（实测 curl 直连/代理都超时）时这一步会以 `TypeError: fetch failed`
  # 失败。此时在 makepkg 前加一个镜像变量即可，缓存键随 URL 变、命中后只多拉那份 6.7KB 清单：
  #   ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/ makepkg -C -s --nocheck
  # 该镜像的清单与 GitHub 官方那份逐字节相同，CI（GitHub runner）不需要这个变量。
  node apps/desktop/node_modules/electron/install.js

  # 只要未打包目录：Arch 包直接把 linux-unpacked 装进 /opt，不需要再套一层 AppImage/deb/rpm。
  "$PNPM" --dir apps/desktop run package:linux:x64:dir
}

package() {
  cd "$_srcdirname"

  local unpacked="apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/linux-unpacked"
  if [[ ! -d "$unpacked" ]]; then
    error "找不到 $unpacked，构建产物路径可能变了"
    return 1
  fi

  install -d "$pkgdir/opt/deepseek-harness-desktop"
  cp -a "$unpacked"/. "$pkgdir/opt/deepseek-harness-desktop/"

  # 可执行文件名由上游 linux.executableName 决定（补丁 0003），是 deepseek-harness。
  install -d "$pkgdir/usr/bin"
  ln -s /opt/deepseek-harness-desktop/deepseek-harness "$pkgdir/usr/bin/deepseek-harness"

  # .desktop 照上游 deb/rpm 里 electron-builder 生成的那一份写，只改安装前缀。
  install -d "$pkgdir/usr/share/applications"
  cat > "$pkgdir/usr/share/applications/deepseek-harness.desktop" <<'EOF'
[Desktop Entry]
Name=DeepSeek Harness
Exec="/opt/deepseek-harness-desktop/deepseek-harness" %U
Terminal=false
Type=Application
Icon=deepseek-harness
StartupWMClass=deepseek-harness
Comment=Electron desktop shell for a bundled dsh runtime and external plugins
MimeType=x-scheme-handler/dsh;
Categories=Development;
EOF

  install -Dm644 apps/desktop/resources/icon-macos.svg \
    "$pkgdir/usr/share/icons/hicolor/scalable/apps/deepseek-harness.svg"

  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"

  # 上游的 AppArmor profile 是 fpm 的 deb/rpm target 写进 linux-unpacked 的
  # （FpmTarget 里 copyFile(scripts.appArmor, resourceDir/apparmor-profile)），--dir 构建
  # 没有这个文件。这里照上游模板写一份，路径换成我们的安装前缀。Arch 默认不开 AppArmor，
  # 未启用时这个文件是惰性的；加载交给 .install。
  install -d "$pkgdir/etc/apparmor.d"
  cat > "$pkgdir/etc/apparmor.d/deepseek-harness" <<'EOF'
abi <abi/4.0>,
include <tunables/global>

profile "deepseek-harness" "/opt/deepseek-harness-desktop/deepseek-harness" flags=(unconfined) {
  userns,

  # Site-specific additions and overrides. See local/README for details.
  include if exists <local/deepseek-harness>
}
EOF

  # setuid 位由 .install 按内核是否支持非特权 user namespace 决定，与上游 postinst 一致。
  chmod 0755 "$pkgdir/opt/deepseek-harness-desktop/chrome-sandbox"
}
