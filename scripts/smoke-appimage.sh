#!/usr/bin/env bash
# 在虚拟显示器上真的启动一次打包好的 AppImage，确认它能开出窗口。
#
#   ./scripts/smoke-appimage.sh <目录> [架构标签]
#
# 目录里必须正好有一个 .AppImage。这里只负责解包，起窗口与判据交给 smoke-display.sh ——
# 「真的打开一次」这件事只有一份实现（Arch 包那条冒烟走同一个脚本）。
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

work="$(mktemp -d /tmp/dsh-smoke-XXXXXX)"
trap 'rm -rf "$work"' EXIT

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

bash "$(dirname "${BASH_SOURCE[0]}")/smoke-display.sh" "$appdir/AppRun" "$LABEL" --cwd "$appdir"
