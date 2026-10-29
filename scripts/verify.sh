#!/usr/bin/env bash
# 验证矩阵。逐项检查，失败不中断，最后汇总。
#
#   ./scripts/verify.sh             静态部分：只看产物与打包元数据，不启动应用（CI 跑这个）
#   ./scripts/verify.sh --runtime   额外跑活体矩阵：真的拉起 linux-unpacked，用 DevTools
#                                   协议读渲染文档，结束时自动收掉
#
# 活体部分需要显示器，且刻意只碰临时 DSH_HOME；同时断言真实的 ~/.dsh 未被触碰。
# 每项检查为什么这么判，都写在它自己的注释里。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="$ROOT/upstream"
# 刻意不继承环境里的 DSH_HOME：DSH 会话自身把 DSH_HOME 指向用户真实的 ~/.dsh，直接继承会让
# 构建往正在使用的数据目录里写东西。要换路径请用 DSH_DESKTOP_LINUX_HOME。
export DSH_HOME="${DSH_DESKTOP_LINUX_HOME:-/tmp/dsh-desktop-test}"
if [[ "$DSH_HOME" == "$HOME/.dsh" ]]; then
  echo "错误：DSH_HOME 不能指向 $HOME/.dsh（正在使用的 dsh 数据目录）" >&2
  exit 1
fi

RUNTIME=0
for arg in "$@"; do
  case "$arg" in
    --runtime) RUNTIME=1 ;;
    *) echo "未知参数：$arg" >&2; exit 2 ;;
  esac
done

pass=0; fail=0; skipped=0
ok()   { echo "  [PASS] $1"; pass=$((pass+1)); }
bad()  { echo "  [FAIL] $1"; fail=$((fail+1)); }
skip() { echo "  [SKIP] $1"; skipped=$((skipped+1)); }
# 断言一个字符串包含另一段文本；$3 是给人看的说明。
has()  { if [[ "$1" == *"$2"* ]]; then ok "$3"; else bad "$3（期望包含：$2）"; fi; }

# 会话总线上已注册的 StatusNotifierItem，每行一个 "<bus>/<path>"。
#
# 条目名有两种形态，都得认：Electron ≤41 与 44.1.0 之后注册的是自己的总线名
# （`:1.666/StatusNotifierItem` 或 `org.freedesktop.StatusNotifierItem-<pid>-1/StatusNotifierItem`），
# 而 44.0.0 那种「服务名拼对象路径」的注册会被宿主静默丢弃，不会出现在这里。
tray_items() {
  dbus-send --session --print-reply --dest=org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
    org.freedesktop.DBus.Properties.Get string:org.kde.StatusNotifierWatcher \
    string:RegisteredStatusNotifierItems 2>/dev/null | grep -o 'string "[^"]*"' | cut -d'"' -f2
}

# unsigned 构建的输出目录（见 electron-builder-config.mjs 的 directories.output）
OUT="$UPSTREAM/apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts"
UNPACKED="$OUT/linux-unpacked"
APPDSH="$UNPACKED/resources/app/dsh"
PRIMARY_NODE="$UNPACKED/resources/runtime/primary-runtime/dependencies/node/bin/node"
CLI="$APPDSH/node_modules/@deepseek-ai/dsh/lib/bin.js"

# 探测用的 node：用系统 node 读 built lib，不依赖产物里那份运行时。
NODE="$(command -v node || true)"

# $1 是不是本次启动的 Electron（$APP_PID）的后代：沿 ppid 链上溯。
#
# 回退分支必须带这条判据。跑着同一份产物时，另一个实例的 Host 命令行与 exe 跟本次那份逐字节相同，
# 只按「命令行含 dsh-desktop-host」+「exe 是本次的 PRIMARY_NODE」筛进程会认领别人的进程，于是
# 「App 起来了」「UI 加载出来了」「Host 跑在真 Node 上」这些断言验的其实是别人（2026-10-06 实测：
# 并发实例的 CDP 端口 9224 被报成本次的 Web Host 端口，Host pid 与渲染进程数也跟着串了 —— 那次
# 汇总仍是 31 通过，但活体那几条没有一个字是做给本次实例的）。
is_app_descendant() {
  local p="${1:-}" hops=0
  [[ -n "${APP_PID:-}" && -n "$p" ]] || return 1
  while [[ -n "$p" && "$p" != "0" && "$p" != "1" && $hops -lt 32 ]]; do
    [[ "$p" == "$APP_PID" ]] && return 0
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d '[:space:]')"
    hops=$((hops + 1))
  done
  return 1
}

# 本次活体运行里 Web Host 实际监听的 127.0.0.1 端口（没有则返回非零）。
#
# 上游 0.2.1-alpha.1 起，桌面端默认端口从固定 19387 改成系统分配（apps/desktop-host 传
# `--port 0`，为的是避让 Windows 的保留端口段），所以「起没起来」不能再按固定端口判断 ——
# 那样只会等到超时。首选读应用自己打出来的那行 URL（`dsh web: http://127.0.0.1:<port>/?token=…`，
# rc.2 与 0.2.1 的日志里都是这个格式，它出现就意味着 Host 已经在监听）。
#
# 读不到才退回问监听表：谁是本产物 primary-runtime 那份 Node（Linux 上 Host 跑在它上面，见 0008）。
# 退回时必须排掉 Electron 自己的监听 —— 它把 CDP 套接字的 fd 继承给了 Host 子进程，于是那个端口在
# `ss` 里同时挂在 Electron 主进程与 Host 两个 pid 上（实测 Electron 的 9223 就是这样），
# 只按「Host 的 pid 在监听」去找会把它误认成 Web Host，端口就报错了。还要排掉并发实例：回退
# 认到的进程必须是本次 Electron 的后代（见 is_app_descendant）。
desktop_host_port() {
  local p exe addr port
  if [[ -n "${LIVE:-}" && -f "$LIVE/app.log" ]]; then
    port="$(sed -n 's|.*dsh web: http://127\.0\.0\.1:\([0-9][0-9]*\).*|\1|p' "$LIVE/app.log" | head -1)"
    [[ -n "$port" ]] && { printf '%s' "$port"; return 0; }
  fi
  for p in $(pgrep -f 'dsh-desktop-host' 2>/dev/null); do
    exe="$(readlink -f "/proc/$p/exe" 2>/dev/null)"
    [[ "$exe" == "$(readlink -f "$PRIMARY_NODE")" ]] || continue
    # 别的实例跑的是同一份 PRIMARY_NODE，只有血缘能把它们挡在外面。
    is_app_descendant "$p" || continue
    while read -r addr; do
      port="${addr##*:}"
      if [[ -n "${APP_PID:-}" ]] && ss -ltnpH 2>/dev/null | grep -qE "127\.0\.0\.1:$port[^0-9].*pid=$APP_PID,"; then
        continue
      fi
      printf '%s' "$port"; return 0
    done < <(ss -ltnpH 2>/dev/null | grep -F "pid=$p," | awk '$4 ~ /^127\.0\.0\.1:/ {print $4}')
  done
  return 1
}

# 当前基线的版本：PKGBUILD 的 _tag 去掉 "dsh-v" 前缀（dsh-v0.2.1-alpha.2 → 0.2.1-alpha.2）。产物文件名、
# 打包后的 package.json 用的都是这个版本。
#
# 为什么需要它：只跑了 build.sh --dir 时，$OUT 里还留着上一版基线的 AppImage/deb/rpm，原先的静态
# 检查对它们照样 PASS——验的其实是旧产物（2026-09-29 实测踩到：0.2.0-rc.1 的验证里有三条 PASS 是
# 9 月 26 日那份 0.1.7-rc.2 的包）。旧版本一律 skip 而不是 bad，因为 --dir 之后本来就没有新的
# AppImage/deb/rpm，那是正常状态，只有「拿旧产物当通过」才是缺陷。
EXPECTED_VERSION="$(bash -c 'source "$1" >/dev/null 2>&1; printf %s "${_tag:-}"' _ "$ROOT/PKGBUILD" | sed 's/^dsh-v//')"
if [[ -z "$EXPECTED_VERSION" ]]; then
  echo "错误：从 $ROOT/PKGBUILD 读不到 _tag，无法判断产物版本" >&2
  exit 1
fi

# 从产物文件名里取版本：deepseek-harness-<版本>-linux-<arch>-unsigned.<格式>
artifact_version() {
  sed -n 's/^deepseek-harness-\(.*\)-linux-\(x86_64\|amd64\)-unsigned\.\(AppImage\|deb\|rpm\)$/\1/p' <<<"$(basename "$1")"
}

# 补丁 → 由哪一层覆盖。新增补丁必须在这里登记，否则本脚本直接 FAIL ——
# 0016/0017 落地后 verify.sh 还停在 10-09，就是没有这一步提醒它该更新。
#   verify  = 本脚本的断言覆盖（静态或活体）
#   tests   = 上游桌面单测（S5 跑，不在本脚本里）
#   matrix  = 三发行版 VM 矩阵（本脚本不跑）
#   pending = 已知欠账，尚未补断言（SKIP，不拦 CI）
declare -A PATCH_COVERAGE=(
  [0001]=verify [0002]=verify [0003]=verify [0004]=verify [0005]=verify
  [0006]=verify [0007]=tests  [0008]=verify [0009]=verify [0010]=verify
  [0011]=verify [0012]=verify [0013]=verify [0016]=verify [0017]=verify
  [0018]=matrix
)

echo "== 0. 补丁覆盖登记（防过期）=="
while IFS= read -r patchfile; do
  id="$(basename "$patchfile" | cut -c1-4)"
  case "${PATCH_COVERAGE[$id]:-}" in
    verify|tests|matrix) ;;
    pending)  skip "补丁 $id 尚未有断言（登记为 pending，补上后改成 verify）" ;;
    *)        bad  "补丁 $id 没有覆盖登记：verify.sh 可能过期（补断言或改 PATCH_COVERAGE）" ;;
  esac
done < <(find "$ROOT/patches" -maxdepth 1 -name '[0-9][0-9][0-9][0-9]-*.patch' | sort)
# 反向：登记了但补丁已不存在（退役或改名后忘了删）。
for id in "${!PATCH_COVERAGE[@]}"; do
  compgen -G "$ROOT/patches/$id-*.patch" >/dev/null || skip "覆盖表里的 $id 已没有对应补丁（退役？）"
done

echo "== 1. 产物存在 =="
mapfile -t artifacts < <(find "$OUT" -maxdepth 1 \
  \( -name '*.AppImage' -o -name '*.deb' -o -name '*.rpm' \) 2>/dev/null)
# 只有版本与当前基线一致、或版本取不出来的产物才算「这次要验的」；旧版本记下来给后面跳过。
fresh_artifacts=()
if (( ${#artifacts[@]} > 0 )); then
  for a in "${artifacts[@]}"; do
    a_version="$(artifact_version "$a")"
    if [[ "$a_version" == "$EXPECTED_VERSION" ]]; then
      ok "$(basename "$a") ($(du -h "$a" | cut -f1))"
      fresh_artifacts+=("$a")
    elif [[ -z "$a_version" ]]; then
      bad "$(basename "$a") 的文件名里读不出版本，无法确认它属于当前基线 $EXPECTED_VERSION"
    else
      skip "$(basename "$a") 是 $a_version 的旧产物（当前基线 $EXPECTED_VERSION），跳过；要验它先跑 build.sh --all"
    fi
  done
else
  bad "没找到 AppImage/deb/rpm 产物（$OUT）"
fi

echo "== 2. 未打包目录 =="
if [[ -x "$UNPACKED/deepseek-harness" ]]; then
  ok "linux-unpacked/deepseek-harness"
  # 未打包目录是不是当前基线打出来的：打包后的 package.json 版本就是上游版本。
  if [[ -n "$NODE" && -f "$UNPACKED/resources/app/package.json" ]]; then
    unpacked_version="$("$NODE" -p "require('$UNPACKED/resources/app/package.json').version" 2>/dev/null || true)"
    if [[ "$unpacked_version" == "$EXPECTED_VERSION" ]]; then
      ok "linux-unpacked 的 package.json 版本是 $unpacked_version"
    else
      bad "linux-unpacked 是 $unpacked_version 的产物（当前基线 $EXPECTED_VERSION）——先重跑 build.sh --dir"
    fi
  else
    skip "读不到 linux-unpacked/resources/app/package.json 的版本"
  fi
  # 真 Node 读不了 asar，Linux 上 dsh 必须是一棵真目录树。
  if [[ -d "$APPDSH/node_modules" ]]; then
    ok "resources/app/dsh 是解包目录树（asar 已关闭）"
  else
    bad "resources/app/dsh 不是解包目录树——真 Node 读不了 asar"
  fi
  # 0017：Host 是独立 Node，没有 process.resourcesPath；壳把 resources 根经环境变量传下去。
  # 静态判据是两件事同时成立：runtime 在 resources/ 下（真运行时），resources/app/runtime 不在
  # （asar 关掉后 CLI 自己的推导会指向那里，0008/0017 修的就是这个）。
  if [[ -d "$UNPACKED/resources/runtime" && ! -e "$UNPACKED/resources/app/runtime" ]]; then
    ok "resources/runtime 在、resources/app/runtime 不在（0017 的落点正确）"
  else
    bad "resources 布局不符合 0017（resources/runtime=$( [[ -d "$UNPACKED/resources/runtime" ]] && echo 在 || echo 缺 )，resources/app/runtime=$( [[ -e "$UNPACKED/resources/app/runtime" ]] && echo 在 || echo 缺 )）"
  fi
  # 托盘图：补丁 0013 让 Linux 的托盘指向 resources/tray-linux.png，由 electron-builder 的
  # Linux extraResources 带进来；它不在补丁里（二进制），所以最可能在这里漏掉。
  tray_png="$UNPACKED/resources/tray-linux.png"
  if [[ -f "$tray_png" ]]; then
    tray_dims="$("$NODE" -e '
      const b = require("node:fs").readFileSync(process.argv[1])
      const png = b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
      process.stdout.write(png ? `${b.readUInt32BE(16)}x${b.readUInt32BE(20)}` : "not-png")
    ' "$tray_png" 2>/dev/null)"
    if [[ "$tray_dims" == "64x64" ]]; then
      ok "resources/tray-linux.png 在场且是 64x64 PNG"
    else
      bad "resources/tray-linux.png 内容不符：$tray_dims"
    fi
  else
    bad "resources/tray-linux.png 缺失（Linux 托盘会拿到空图标）"
  fi
else
  skip "linux-unpacked 不存在（还没跑 package:linux:x64:dir）"
fi

echo "== 3. 原生模块 =="
for mod in pty.node; do
  if find "$UPSTREAM/node_modules" -name "$mod" -print -quit 2>/dev/null | grep -q .; then
    ok "$mod 已构建"
  else
    bad "$mod 缺失（node-pty 在 Linux 上无 prebuild）"
  fi
done
if find "$UPSTREAM/node_modules" -path '*sharp*' -name '*.node' -print -quit 2>/dev/null | grep -q .; then
  ok "sharp 原生模块已构建"
else
  bad "sharp 原生模块缺失"
fi

echo "== 4. 打包元数据 =="
# .desktop 决定三件事：菜单项、窗口与任务的关联（StartupWMClass）、以及 dsh:// 的处理者（MimeType）。
# AppImage 的那份在 squashfs 里，用运行时自带的解包开关取，不需要 FUSE。
appimage=""
if (( ${#fresh_artifacts[@]} > 0 )); then
  for a in "${fresh_artifacts[@]}"; do [[ "$a" == *.AppImage ]] && { appimage="$a"; break; }; done
fi
if [[ -n "$appimage" ]]; then
  extract="$(mktemp -d)"
  ( cd "$extract" && "$appimage" --appimage-extract '*.desktop' >/dev/null 2>&1 )
  desktop="$(find "$extract" -name '*.desktop' -print -quit 2>/dev/null)"
  if [[ -n "$desktop" ]]; then
    body="$(cat "$desktop")"
    has "$body" 'MimeType=x-scheme-handler/dsh;' 'AppImage 的 .desktop 注册了 dsh:// 处理者'
    has "$body" 'StartupWMClass=deepseek-harness' 'AppImage 的 .desktop 声明了 StartupWMClass'
    # AppRun 自己会探测 user namespace；写死 --no-sandbox 会让菜单启动的每一次都没有沙箱。
    exec_line="$(grep -m1 '^Exec=' "$desktop" || true)"
    if [[ "$exec_line" == *'--no-sandbox'* ]]; then
      bad "AppImage 的 Exec 写死了 --no-sandbox：$exec_line"
    else
      ok "AppImage 的 Exec 没有写死 --no-sandbox（$exec_line）"
    fi
  else
    skip "没能从 AppImage 里取出 .desktop"
  fi
  rm -rf "$extract"
else
  skip "没有当前基线（$EXPECTED_VERSION）的 AppImage，跳过 .desktop 检查"
fi

# PKGBUILD 手写一份 .desktop（Arch 包不走 fpm），内容取自上游 deb 里 electron-builder 生成的那份。
pkg_desktop="$(awk '/applications\/deepseek-harness\.desktop/{f=1;next} f&&/^EOF$/{exit} f' "$ROOT/PKGBUILD" 2>/dev/null)"
if [[ -n "$pkg_desktop" ]]; then
  has "$pkg_desktop" 'MimeType=x-scheme-handler/dsh;' 'PKGBUILD 的 .desktop 注册了 dsh:// 处理者'
  has "$pkg_desktop" 'StartupWMClass=deepseek-harness' 'PKGBUILD 的 .desktop 声明了 StartupWMClass'
  has "$pkg_desktop" 'Exec="/opt/deepseek-harness-desktop/deepseek-harness" %U' 'PKGBUILD 的 Exec 用了安装前缀'
else
  skip "没能从 PKGBUILD 里取出 .desktop"
fi

# 策略通道是 Windows/macOS 专有的，Linux 产物里不该出现这个字段（补丁 0010）。
if [[ -f "$APPDSH/package.json" ]]; then
  if grep -q 'dshMandatoryUpdatePolicy' "$APPDSH/package.json"; then
    bad "Linux 产物的 manifest 里出现了 dshMandatoryUpdatePolicy"
  else
    ok "Linux 产物的 manifest 里没有策略字段"
  fi
else
  skip "没有打包后的 manifest，跳过策略字段检查"
fi

echo "== 5. 共享根与 profile 独占（不需要 GUI）=="
if [[ -n "$NODE" && -f "$APPDSH/node_modules/@deepseek-ai/dsh-home-paths/lib/index.js" ]]; then
  read -r home_precedence home_blank <<<"$("$NODE" --input-type=module -e "
    const { resolveDshHome, defaultDshHome } = await import('$APPDSH/node_modules/@deepseek-ai/dsh-home-paths/lib/index.js')
    process.stdout.write([
      resolveDshHome(undefined, { DSH_HOME: '/tmp/x' }) === '/tmp/x',
      resolveDshHome(undefined, { DSH_HOME: '   ' }) === defaultDshHome(),
    ].join(' '))
  " 2>/dev/null)"
  [[ "$home_precedence" == true ]] && ok 'DSH_HOME 覆盖默认根' || bad 'DSH_HOME 没有覆盖默认根'
  [[ "$home_blank" == true ]] && ok '空白的 DSH_HOME 回落到 ~/.dsh' || bad '空白 DSH_HOME 的处理与预期不符'
else
  skip "缺少 dsh-home-paths 的 built lib，跳过根解析检查"
fi

# Linux 上客户端把 x-client-platform 报成 desktop-mac：platform === 'win32' ? 'desktop-win' : 'desktop-mac'。
# 这是记录在案的行为（不是缺陷），但它意味着 Platform 侧看到的是一台 macOS 客户端。
if [[ -n "$NODE" && -f "$APPDSH/node_modules/@deepseek-ai/dsh-deepseek-account/lib/index.js" ]]; then
  platform_header="$("$NODE" --input-type=module -e "
    const { platformClientHeaders } = await import('$APPDSH/node_modules/@deepseek-ai/dsh-deepseek-account/lib/index.js')
    const c = { version: '0', locale: 'en-US', timezoneOffsetSeconds: 0 }
    process.stdout.write(['linux', 'darwin', 'null'].map(p =>
      p === 'null' ? platformClientHeaders(null, c)['x-client-platform']
                   : platformClientHeaders(p, c)['x-client-platform']).join(' '))
  " 2>/dev/null)"
  if [[ "$platform_header" == 'desktop-mac desktop-mac web' ]]; then
    ok "客户端身份：linux→desktop-mac（已记录）、darwin→desktop-mac、null→web"
  else
    bad "客户端身份与记录不符：$platform_header"
  fi
else
  skip "缺少 deepseek-account 的 built lib，跳过客户端身份检查"
fi

# desktop profile 由 Electron 独占：CLI 连参数层面都拒绝它，所以两者不可能写同一个 profile。
if [[ -x "$PRIMARY_NODE" && -f "$CLI" ]]; then
  cli_out="$("$PRIMARY_NODE" "$CLI" --profile desktop --dump-config 2>&1)"; cli_rc=$?
  if (( cli_rc != 0 )) && [[ "$cli_out" == *'managed exclusively by the Electron application'* ]]; then
    ok "CLI 拒绝 desktop profile（exit $cli_rc）"
  else
    bad "CLI 没有拒绝 desktop profile：exit=$cli_rc $cli_out"
  fi
else
  skip "缺少产物里的 CLI，跳过 desktop profile 独占检查"
fi

if (( RUNTIME )); then
  echo "== 6. 活体矩阵（--runtime）=="
  if [[ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
    skip "没有显示器（WAYLAND_DISPLAY 与 DISPLAY 都为空）"
  else
    APP="$UNPACKED/deepseek-harness"
    LIVE="$(mktemp -d /tmp/dsh-verify-live-XXXXXX)"
    CDP_PORT=9223

    # 已经有别的桌面端在跑不再是障碍。Electron 的单实例锁（apps/desktop/src/single-instance.ts）
    # 按 userData 目录判定，而 Linux 上 userData = $XDG_CONFIG_HOME/<app.name>，所以这次活体运行
    # 带一个隔离的 XDG_CONFIG_HOME 就能与用户正在用的那份并存，也顺手不会碰对方真实的 userData。
    # 代价在托盘断言：宿主里可能同时挂着「别人那项」，只按产品名去认会认错人 —— 所以启动前先给
    # 已注册的项拍个快照，下面只认本次新增的。
    if pgrep -f '[d]eepseek-harness$' >/dev/null 2>&1; then
      echo "  [注意] 已有桌面端在跑；本次活体运行使用隔离的 userData（$LIVE/config）"
    fi
    tray_items_before=""
    if command -v dbus-send >/dev/null 2>&1; then
      tray_items_before="$(tray_items)"
    fi
    APP_PID=""
    cleanup() {
      [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null
      rm -rf "$LIVE"
    }
    trap cleanup EXIT

    # 纪律判据：整个活体过程不许改真实的 ~/.dsh。
    # 比的是「跑前跑后是否一致」，不是「目录是否存在」—— 只要这台机器上装过并用过桌面端，
    # ~/.dsh/profiles/desktop 就必然存在（已装版用的就是真实的 DSH_HOME），断言不存在的话
    # 每次都会误报。指纹取文件名/类型/大小/mtime，改动或新增都会被看出来。
    real_desktop_fingerprint() {
      local d="$HOME/.dsh/profiles/desktop"
      [[ -e "$d" ]] || { printf 'absent\n'; return 0; }
      find "$d" -mindepth 1 -printf '%P\t%y\t%s\t%T@\n' 2>/dev/null | sort
    }
    real_desktop_before="$(real_desktop_fingerprint)"

    # 哨兵：桌面端只许动 profiles/desktop 与共享根，不许碰别的 profile。
    mkdir -p "$LIVE/profiles/web"
    echo "sentinel" >"$LIVE/profiles/web/SENTINEL"
    sentinel_before="$(sha256sum "$LIVE/profiles/web/SENTINEL" | cut -d' ' -f1)"

    DSH_HOME="$LIVE" XDG_CONFIG_HOME="$LIVE/config" "$APP" --remote-debugging-port="$CDP_PORT" >"$LIVE/app.log" 2>&1 &
    APP_PID=$!
    app_port=""
    for _ in $(seq 1 60); do
      app_port="$(desktop_host_port)" && break
      kill -0 "$APP_PID" 2>/dev/null || break
      sleep 1
    done

    if [[ -n "$app_port" ]]; then
      ok "应用起来了，Web Host 在 127.0.0.1:$app_port 监听（--port 0，端口由系统分配）"

      # 用 DevTools 协议问渲染文档本身，而不是只看进程在不在。
      cat >"$LIVE/cdp.mjs" <<'CDP'
const port = process.argv[2]
const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()
for (const t of list.filter(t => t.type === 'page')) {
  const ws = new WebSocket(t.webSocketDebuggerUrl)
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej })
  const value = await new Promise(res => {
    ws.addEventListener('message', ev => {
      const m = JSON.parse(ev.data)
      if (m.id === 1) res(m.result?.result?.value ?? '')
    })
    ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: {
      expression: `location.href + ' ' + document.querySelectorAll('*').length`, returnByValue: true } }))
  })
  console.log(value)
  ws.close()
}
CDP
      # 端口一开始监听时 renderer 往往还在加载，所以要等到节点数连续两次一样（渲染稳定）为止。
      cdp_out=""; app_nodes=""; prev_nodes=""
      for _ in $(seq 1 60); do
        cdp_out="$(env -u NODE_OPTIONS -u NODE_USE_ENV_PROXY -u http_proxy -u https_proxy \
          -u HTTP_PROXY -u HTTPS_PROXY "$NODE" "$LIVE/cdp.mjs" "$CDP_PORT" 2>/dev/null)"
        app_page="$(grep -m1 '^dsh-app://' <<<"$cdp_out" || true)"
        cur_nodes="${app_page##* }"
        if [[ "$cur_nodes" =~ ^[0-9]+$ ]] && (( cur_nodes > 100 )) && [[ "$cur_nodes" == "$prev_nodes" ]]; then
          app_nodes="$cur_nodes"; break
        fi
        prev_nodes="$cur_nodes"
        sleep 1
      done
      if [[ -n "$app_nodes" ]]; then
        ok "dsh-app:// 加载出了 UI（$app_nodes 个 DOM 节点，已稳定）"
      else
        bad "dsh-app:// 没有渲染出 UI（最后一次探测：${cdp_out:-无输出}）"
      fi

      # 0016：Linux 用页内 caption 代替原生菜单栏。上游自己的单测断言的就是这个标记
      # （tests/preload-windows.client.spec.ts 在 linux 上期望 data-windows-titlebar 为 true）。
      # 菜单宿主 [data-windows-menu] 由 preload 动态创建，菜单本体在它的 shadow root 里。
      cat >"$LIVE/eval.mjs" <<'CDP'
const [port, expr] = process.argv.slice(2)
const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()
const page = list.find(t => t.type === 'page' && t.url.startsWith('dsh-app://app'))
if (!page) process.exit(3)
const ws = new WebSocket(page.webSocketDebuggerUrl)
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej })
const value = await new Promise(res => {
  ws.addEventListener('message', ev => {
    const m = JSON.parse(ev.data)
    if (m.id === 1) res(JSON.stringify(m.result?.result?.value))
  })
  ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression: expr, returnByValue: true } }))
})
console.log(value)
ws.close()
CDP
      cdp_eval() {
        env -u NODE_OPTIONS -u NODE_USE_ENV_PROXY -u http_proxy -u https_proxy \
          -u HTTP_PROXY -u HTTPS_PROXY "$NODE" "$LIVE/eval.mjs" "$CDP_PORT" "$1" 2>/dev/null | tail -1
      }
      has_titlebar="$(cdp_eval 'document.documentElement.hasAttribute("data-windows-titlebar")')"
      if [[ "$has_titlebar" == true ]]; then
        ok "0016：Linux 自绘标题栏标记在场（data-windows-titlebar）"
      else
        bad "0016：主窗口没有 data-windows-titlebar（拿到 ${has_titlebar:-空}）"
      fi
      has_menu="$(cdp_eval 'Boolean(document.querySelector("[data-windows-menu]"))')"
      if [[ "$has_menu" == true ]]; then
        ok "0016：页内 caption 菜单宿主已挂载（[data-windows-menu]）"
      else
        bad "0016：页内 caption 菜单宿主缺失（原生菜单栏可能没被隐藏）"
      fi

      # Host 必须跑在 primary-runtime 自带的真 Node 上（Electron 的 node 模式下 sharp 会段错误）。
      # 同样只认本次实例的后代：并发跑同构建的另一个实例时，它的 Host 也是这份 PRIMARY_NODE。
      host_pid=""
      for p in $(pgrep -f 'dsh-desktop-host' 2>/dev/null); do
        if [[ "$(readlink -f "/proc/$p/exe" 2>/dev/null)" == "$(readlink -f "$PRIMARY_NODE")" ]] \
          && is_app_descendant "$p"; then
          host_pid="$p"; break
        fi
      done
      if [[ -n "$host_pid" ]]; then
        ok "Host 进程跑在 primary-runtime 的真 Node 上（pid $host_pid）"
        # 0017：独立 Node 的 Host 没有 process.resourcesPath，壳通过 DSH_DESKTOP_RESOURCES_PATH
        # 把安装树的 resources 根传下去。直接读 /proc/<pid>/environ，不依赖 UI 行为。
        if tr '\0' '\n' <"/proc/$host_pid/environ" 2>/dev/null \
             | grep -qxF "DSH_DESKTOP_RESOURCES_PATH=$UNPACKED/resources"; then
          ok "0017：Host 收到了安装树的 resources 根"
        else
          bad "0017：Host 环境里没有 DSH_DESKTOP_RESOURCES_PATH=$UNPACKED/resources"
        fi
      else
        bad "没有找到跑在 primary-runtime Node 上的 Host 进程"
      fi

      # 沙箱：渲染进程在独立 user namespace 里且 seccomp 生效，主进程不在。
      # 计数同样限定本次实例的后代，否则并发实例的渲染进程会把 $renderers 撑大，
      # 那几条断言看起来通过，实际分子分母都不是本次这份。
      main_ns="$(readlink "/proc/$APP_PID/ns/pid" 2>/dev/null)"
      sandboxed=0; renderers=0
      for p in $(pgrep -f -- '--type=renderer' 2>/dev/null); do
        [[ "$(readlink -f "/proc/$p/exe" 2>/dev/null)" == "$(readlink -f "$APP")" ]] || continue
        is_app_descendant "$p" || continue
        renderers=$((renderers+1))
        [[ "$(readlink "/proc/$p/ns/pid" 2>/dev/null)" != "$main_ns" ]] || continue
        grep -q '^Seccomp:\s*2' "/proc/$p/status" 2>/dev/null && sandboxed=$((sandboxed+1))
      done
      if (( renderers > 0 && sandboxed == renderers )); then
        ok "全部 $renderers 个渲染进程都在独立 user namespace 里且 seccomp 生效"
      else
        bad "渲染进程沙箱不完整（$sandboxed/$renderers）"
      fi

      # 托盘：Linux 上它由 Electron 进程内的 StatusNotifierItem 提供。两条判据 —— 宿主真的注册了
      # 我们的项，且该项的菜单里读得到带产品名的条目（打开 + 退出）。第二条才是关键：菜单要的
      # libdbusmenu-glib 是 dlopen 的，缺了它图标照样出现、菜单却是空的，等于没有退出入口，
      # 而 ldd 和 namcap 都看不见这件事。
      # 产品名在两种界面语言里都是 "DeepSeek Harness"，所以断言与语言无关；「必须是本次启动新增的
      # 那一项」这条见启动前的快照。
      # 注册是异步的（实测要几秒，取决于面板何时来取），所以这里轮询而不是只看一眼。
      if command -v dbus-send >/dev/null 2>&1 \
        && dbus-send --session --print-reply --dest=org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
             org.freedesktop.DBus.Properties.Get string:org.kde.StatusNotifierWatcher \
             string:RegisteredStatusNotifierItems >/dev/null 2>&1; then
        tray_item=""; tray_labels=0
        for _ in $(seq 1 30); do
          for item in $(tray_items); do
            # 只认本次启动新增的项：已有桌面端在跑时，宿主里那份属于别人。
            grep -qxF "$item" <<<"$tray_items_before" && continue
            bus="${item%%/*}"; item_path="/${item#*/}"
            dbus-send --session --print-reply --dest="$bus" "$item_path" \
              org.freedesktop.DBus.Properties.Get string:org.kde.StatusNotifierItem string:ToolTip 2>/dev/null \
              | grep -q 'DeepSeek Harness' || continue
            # 回复里印的是 `variant object path "/com/canonical/dbusmenu"`，不是调用时那种 objectpath。
            menu_path="$(dbus-send --session --print-reply --dest="$bus" "$item_path" \
              org.freedesktop.DBus.Properties.Get string:org.kde.StatusNotifierItem string:Menu 2>/dev/null \
              | sed -n 's/.*object path "\([^"]*\)".*/\1/p' | head -1)"
            [[ -n "$menu_path" ]] || continue
            labels="$(dbus-send --session --print-reply --dest="$bus" "$menu_path" \
              com.canonical.dbusmenu.GetLayout int32:0 int32:-1 array:string: 2>/dev/null \
              | grep -o 'string "[^"]*"' | grep -c 'DeepSeek Harness')"
            if (( labels >= 2 )); then
              tray_item="$item"; tray_labels="$labels"; break 2
            fi
          done
          sleep 1
        done
        if [[ -n "$tray_item" ]]; then
          ok "托盘已注册（$tray_item），菜单里读到 $tray_labels 个带产品名的条目（打开 + 退出）"
        else
          bad "没找到本次启动新增的、菜单可读的托盘项——缺 libdbusmenu-glib 时就是这个症状"
        fi
      else
        skip "没有 StatusNotifierWatcher（非 KDE，或没有会话总线），跳过托盘检查"
      fi

      # 共享根：工作区存储与凭据落在根上，而不是某个 profile 里。
      #
      # 这里原本断言 sessions/ 里出现 session.v*.jsonl（会话由 Host 在启动后异步建立）。那条的
      # 前提从上游 0.2.0 起就不成立了：全新根上的首启停在「Choose a workspace to start /
      # No sessions yet」，应用不再自动建会话 —— 2026-10-04 对照实测，0.2.1-alpha.1 与已安装的
      # 0.2.0rc2-1 在同一个隔离根上都不建，把用户真实 userData 拷进去也一样。改成断言应用确实把
      # 工作区存储写进了共享根：这是首启状态下「共享根活得起来」能拿到的最直接证据。要验会话本身，
      # 得先在 UI 里选一个工作区。
      [[ -d "$LIVE/profiles/desktop" ]] && ok 'profiles/desktop 已建立' || bad 'profiles/desktop 没有建立'
      workspace_store=0
      for _ in $(seq 1 30); do
        if [[ -s "$LIVE/storages/workspace.json" && -n "$NODE" ]] \
          && "$NODE" -e 'const j = require(process.argv[1]); process.exit(j?.unit?.name === "workspace" && j?.global?.initialized === true ? 0 : 1)' \
               "$LIVE/storages/workspace.json" 2>/dev/null; then
          workspace_store=1; break
        fi
        sleep 1
      done
      (( workspace_store )) && ok '共享根里出现了已初始化的工作区存储（storages/workspace.json）' \
                            || bad '共享根里没有可用的工作区存储（storages/workspace.json）'
      [[ -f "$LIVE/.credentials.yaml" ]] && ok '共享根里出现了凭据文件' || bad '共享根里没有凭据文件'
      if [[ "$(sha256sum "$LIVE/profiles/web/SENTINEL" | cut -d' ' -f1)" == "$sentinel_before" ]]; then
        ok 'profiles/web 的哨兵未被触碰'
      else
        bad 'profiles/web 被改动了'
      fi

      # 交叉验证：CLI 在同一个根上跑，profiles/desktop 必须逐字节不变。
      if [[ -x "$PRIMARY_NODE" && -f "$CLI" ]]; then
        desktop_before="$(find "$LIVE/profiles/desktop" -type f -exec sha256sum {} \; 2>/dev/null | sort)"
        DSH_HOME="$LIVE" "$PRIMARY_NODE" "$CLI" --profile web --dump-config >/dev/null 2>&1
        desktop_after="$(find "$LIVE/profiles/desktop" -type f -exec sha256sum {} \; 2>/dev/null | sort)"
        if [[ -n "$desktop_before" && "$desktop_before" == "$desktop_after" ]]; then
          ok 'CLI 在同一根上跑完，profiles/desktop 逐字节未变'
        else
          bad 'CLI 动了 profiles/desktop'
        fi
      fi
    else
      bad "应用没能在 60 秒内起来（Host 没有监听端口，日志见下）"
      sed 's/^/         /' "$LIVE/app.log" | tail -10
    fi

    # 纪律：整个活体过程不许碰真实的 ~/.dsh。
    if [[ "$(real_desktop_fingerprint)" == "$real_desktop_before" ]]; then
      if [[ "$real_desktop_before" == absent ]]; then
        ok '真实的 ~/.dsh 未被触碰（没有 profiles/desktop）'
      else
        ok '真实的 ~/.dsh/profiles/desktop 存在，但本次活体过程未改动它'
      fi
    else
      bad '真实的 ~/.dsh/profiles/desktop 被改动了——桌面端泄漏到了正在使用的数据目录'
    fi

    kill "$APP_PID" 2>/dev/null
    wait "$APP_PID" 2>/dev/null
    APP_PID=""
  fi
else
  echo "== 6. 活体矩阵（--runtime）=="
  skip "没给 --runtime"
fi

echo "== 7. 端口不冲突 =="
if ss -ltnp 2>/dev/null | grep -q ':3080'; then
  ok "3080 上的 web GUI 未受影响"
else
  skip "3080 没在监听"
fi

echo
echo "== 汇总：$pass 通过 / $fail 失败 / $skipped 跳过 =="
(( fail == 0 ))
