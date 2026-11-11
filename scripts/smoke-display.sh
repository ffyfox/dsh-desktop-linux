#!/usr/bin/env bash
# 在虚拟显示器上启动一个已打包的可执行文件，确认它真的开出了窗口。
#
#   ./scripts/smoke-display.sh <可执行文件> [标签] [--cwd <目录>] [-- 额外参数...]
#
# 判据（与 AppImage 那套同源，两处只此一份实现）：
#   1. 主进程在启动阶段退出；
#   2. 日志里出现启动失败的信息；
#   3. 出现带「启动失败」标题的对话框，或者 90 秒内没有任何窗口。
#
# 环境：SMOKE_DISPLAY（默认 :99）、SMOKE_OUT（截图目录，默认 /tmp/dsh-smoke）。
# 调用方负责先把可执行文件装好；这里只负责「起得来、有窗口」。
set -uo pipefail

exec_path="${1:-}"
label="${2:-$(uname -m)}"
if [[ -z "$exec_path" ]]; then
  echo "用法：$0 <可执行文件> [标签] [--cwd 目录] [-- 额外参数...]" >&2
  exit 2
fi
shift 2 2>/dev/null || shift 1 || true
cwd=""
extra=()
while (( $# )); do
  case "$1" in
    --cwd) cwd="${2:-}"; shift 2 ;;
    --) shift; extra+=("$@"); break ;;
    *) extra+=("$1"); shift ;;
  esac
done

for tool in Xvfb xdotool; do
  command -v "$tool" >/dev/null 2>&1 || { echo "缺少 $tool（CI 的依赖安装步骤应该先装好）" >&2; exit 2; }
done
[[ -x "$exec_path" ]] || { echo "失败：$exec_path 不可执行" >&2; exit 2; }

# 启动失败的对话框标题（en / zh 两种界面语言）。
fatal_titles=('DeepSeek Harness is unavailable' 'DeepSeek Harness 无法使用')
fatal_log='DeepSeek Harness is unavailable|DeepSeek Harness 无法使用|Unhandled|Application could not start'

display="${SMOKE_DISPLAY:-:99}"
out="${SMOKE_OUT:-/tmp/dsh-smoke}"
work="$(mktemp -d /tmp/dsh-smoke-run-XXXXXX)"
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

echo "== 目标：$exec_path（$label）=="
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
( cd "${cwd:-$PWD}" && exec setsid "$exec_path" --ozone-platform=x11 --no-sandbox --disable-gpu --disable-dev-shm-usage "${extra[@]+${extra[@]}}" ) >"$work/startup.log" 2>&1 &
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
  import -window root "$out/startup-$label.png" 2>/dev/null || true
  echo "== 截图：$out/startup-$label.png =="
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
