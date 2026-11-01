#!/usr/bin/env bash
# 在虚拟显示器上真的启动一次打包好的 AppImage，确认它能开出窗口。
#
#   ./scripts/smoke-appimage.sh <目录> [架构标签]
#
# 目录里必须正好有一个 .AppImage。判据三条，任意一条成立就失败：
#   1. 主进程在启动阶段退出；
#   2. 日志里出现启动失败的信息；
#   3. 出现带「启动失败」标题的对话框，或者 90 秒内没有任何窗口。
#
# 打包成功只说明文件格式正确，不说明应用能启动 —— arm64 上最容易犯的错就是
# 箱子里装的是 x64 零件。这个脚本是发布前最后一道「真的打开一次」的门。
set -uo pipefail

DIR="${1:-}"
LABEL="${2:-$(uname -m)}"
if [[ -z "$DIR" ]]; then
  echo "用法：$0 <AppImage 所在目录> [架构标签]" >&2
  exit 2
fi

for tool in Xvfb xdotool; do
  command -v "$tool" >/dev/null 2>&1 || { echo "缺少 $tool（CI 的依赖安装步骤应该先装好）" >&2; exit 2; }
done

shopt -s nullglob
images=("$DIR"/*.AppImage)
if (( ${#images[@]} != 1 )); then
  echo "失败：$DIR 里应当正好有一个 .AppImage，实际 ${#images[@]} 个" >&2
  exit 1
fi
image="$(cd "$(dirname "${images[0]}")" && pwd)/$(basename "${images[0]}")"

# 启动失败的对话框标题（en / zh 两种界面语言）。
fatal_titles=('DeepSeek Harness is unavailable' 'DeepSeek Harness 无法使用')
fatal_log='DeepSeek Harness is unavailable|DeepSeek Harness 无法使用|Unhandled|Application could not start'

work="$(mktemp -d /tmp/dsh-smoke-XXXXXX)"
display="${SMOKE_DISPLAY:-:99}"
out="${SMOKE_OUT:-/tmp/dsh-smoke}"
mkdir -p "$out" "$work/home/.config" "$work/xdg" "$work/tmp" "$work/dsh"
app_pid=""
xvfb_pid=""
cleanup() {
  # setsid 让应用成为新进程组的组长，退出时连同 Host 子进程一起收掉。
  [[ -n "$app_pid" ]] && kill -9 -- -"$app_pid" 2>/dev/null
  [[ -n "$xvfb_pid" ]] && kill -9 "$xvfb_pid" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

echo "== 目标：$image（$LABEL，$(stat -c %s "$image") 字节）=="
echo "== 解包 =="
# AppImage 挂载需要 FUSE，CI 里没有；运行时自带的不挂载解包开关就够了。
( cd "$work" && "$image" --appimage-extract ) >"$work/extract.log" 2>&1
appdir="$work/squashfs-root"
if [[ ! -x "$appdir/AppRun" ]]; then
  echo "失败：解包后没有可执行的 AppRun" >&2
  sed -n '1,40p' "$work/extract.log" >&2
  exit 1
fi

echo "== 虚拟显示器 $display =="
Xvfb "$display" -screen 0 1280x1024x24 -nolisten tcp >/dev/null 2>&1 &
xvfb_pid=$!
export DISPLAY="$display"
# 强制走 X11：开发机上可能继承 WAYLAND_DISPLAY，而 XDG_RUNTIME_DIR 已经隔离，
# Wayland 连接会失败；CI 的 Xvfb 本来也只有 X11。
unset WAYLAND_DISPLAY
export HOME="$work/home"
export XDG_CONFIG_HOME="$work/home/.config"
export XDG_RUNTIME_DIR="$work/xdg"
export TMPDIR="$work/tmp"
export DSH_HOME="$work/dsh"
sleep 3

echo "== 启动 =="
( cd "$appdir" && exec setsid ./AppRun --ozone-platform=x11 --no-sandbox --disable-gpu --disable-dev-shm-usage ) >"$work/startup.log" 2>&1 &
app_pid=$!

titles=""
for _ in $(seq 1 45); do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    echo "失败：应用在启动阶段退出" >&2
    sed -n '1,60p' "$work/startup.log" >&2
    exit 1
  fi
  if grep -qaE "$fatal_log" "$work/startup.log" 2>/dev/null; then
    echo "失败：日志里出现启动失败信息" >&2
    grep -aE "$fatal_log" "$work/startup.log" | head -5 >&2
    exit 1
  fi
  found="$(xdotool search --pid "$app_pid" --onlyvisible --name '.' getwindowname 2>/dev/null | sort -u || true)"
  if [[ -n "$found" ]]; then
    # 启动失败的对话框和真窗口可能先后出现，多等一会儿再采样一次。
    sleep 10
    titles="$(xdotool search --pid "$app_pid" --onlyvisible --name '.' getwindowname 2>/dev/null | sort -u || true)"
    break
  fi
  sleep 2
done

echo "== 窗口标题 =="
printf '%s\n' "$titles" | sed 's/^/    /'
if command -v import >/dev/null 2>&1 && [[ -n "$titles" ]]; then
  import -window root "$out/startup-$LABEL.png" 2>/dev/null || true
  echo "== 截图：$out/startup-$LABEL.png =="
fi

for title in "${fatal_titles[@]}"; do
  if printf '%s' "$titles" | grep -qF "$title"; then
    echo "失败：应用弹出了启动失败对话框（$title）" >&2
    sed -n '1,60p' "$work/startup.log" >&2
    exit 1
  fi
done
if [[ -z "$titles" ]]; then
  echo "失败：90 秒内没有出现任何窗口" >&2
  sed -n '1,60p' "$work/startup.log" >&2
  exit 1
fi

echo "通过：应用启动并开出了窗口"
