#!/usr/bin/env bash
# 在 ./upstream 里构建 Linux 桌面端。
#
#   ./scripts/build.sh --dir        # 只出未打包目录（快，先验证能不能起来）
#   ./scripts/build.sh              # 默认 AppImage
#   ./scripts/build.sh --deb        # 只出 .deb
#   ./scripts/build.sh --rpm        # 只出 .rpm（需要系统装 rpmbuild，Arch 上是 rpm-tools）
#   ./scripts/build.sh --all        # AppImage + deb + rpm
#
# 每次只出被点名的格式：整条流水线（build:official / release:pack / prepare:*）才是耗时大头，
# 多打一种格式只多一次 fpm/AppImage 打包，所以分开跑更快，也更容易定位失败。
#
# 环境变量：
#   DSH_DESKTOP_LINUX_HOME  隔离的 dsh 数据目录，默认 /tmp/dsh-desktop-test
#                           （刻意不读 DSH_HOME，见下方注释）
#
# 产物落在 .desktop-build/targets/linux-x64/unsigned-artifacts/（unsigned 构建）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="$ROOT/upstream"
# 刻意不继承环境里的 DSH_HOME：DSH 会话自身把 DSH_HOME 指向用户真实的 ~/.dsh，直接继承会让
# 构建往正在使用的数据目录里写东西。要换路径请用 DSH_DESKTOP_LINUX_HOME。
export DSH_HOME="${DSH_DESKTOP_LINUX_HOME:-/tmp/dsh-desktop-test}"
if [[ "$DSH_HOME" == "$HOME/.dsh" ]]; then
  echo "错误：DSH_HOME 不能指向 $HOME/.dsh（正在使用的 dsh 数据目录）" >&2
  exit 1
fi

[[ -d "$UPSTREAM/apps/desktop" ]] || { echo "找不到 $UPSTREAM/apps/desktop，先跑 fetch-upstream.sh" >&2; exit 1; }

# --- pnpm 11（仓库要求 packageManager: pnpm@11.28.5）---
# 除了版本，还要求「它交给脚本的入口能被 node 执行」——理由与探法见 scripts/select-pnpm.sh。
# shellcheck source=scripts/select-pnpm.sh
source "$ROOT/scripts/select-pnpm.sh"

# DSH_DESKTOP_TARGET_FORMATS 是一次构建的选择器（和 DSH_DESKTOP_TARGET_PLATFORM/ARCH 同类），
# 不是发布设置，所以它只能从环境传，不能写进 .env.linux。
MODE="${1:---appimage}"
case "$MODE" in
  --dir)      SCRIPT="package:linux:x64:dir"; FORMATS="" ;;
  --appimage) SCRIPT="package:linux:x64";     FORMATS="AppImage" ;;
  --deb)      SCRIPT="package:linux:x64";     FORMATS="deb" ;;
  --rpm)      SCRIPT="package:linux:x64";     FORMATS="rpm" ;;
  --all)      SCRIPT="package:linux:x64";     FORMATS="AppImage,deb,rpm" ;;
  *) echo "未知参数：$MODE" >&2; exit 2 ;;
esac

# --- Linux 发布设置文件（上游按平台读 dotenv，Linux 用 .env.linux）---
# APP_ID 必填；MAINTAINER/HOMEPAGE 只有打 deb/rpm 时才要（fpm 的 control 文件缺这两项会拒收）。
# 强制更新策略通道是 Windows/macOS 专有的：Linux 产物没有更新通道，所以 Linux 版不嵌入策略、
# 也不轮询。
ENV_FILE="$UPSTREAM/apps/desktop/.env.linux"
ENV_EXAMPLE="$ENV_FILE.example"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "==> $ENV_FILE 不存在，从 .env.linux.example 生成"
  cp "$ENV_EXAMPLE" "$ENV_FILE"
else
  # .env.linux 是 git-ignored 的本机文件，模板后来新增的键不会自动出现。
  missing="$(comm -23 <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*' "$ENV_EXAMPLE" | sort -u) \
                      <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*' "$ENV_FILE" | sort -u) | tr '\n' ' ')"
  if [[ -n "${missing// /}" ]]; then
    echo "==> 提示：$ENV_FILE 里没有模板中的设置：$missing" >&2
    echo "    对照 $ENV_EXAMPLE 补上（打 deb/rpm 需要 MAINTAINER 与 HOMEPAGE）" >&2
  fi
fi

echo "==> DSH_HOME=$DSH_HOME"
echo "==> apps/desktop script: $SCRIPT${FORMATS:+ (formats: $FORMATS)}"
mkdir -p "$DSH_HOME"

# 原生模块现状（实测）：node-pty 与 sharp 的 linux-x64 二进制都随 pnpm install 就位，
# 不需要额外编译。
if ! find "$UPSTREAM/node_modules" -name 'pty.node' -print -quit 2>/dev/null | grep -q .; then
  echo "==> 警告：没找到 pty.node" >&2
fi

if [[ -n "$FORMATS" ]]; then
  export DSH_DESKTOP_TARGET_FORMATS="$FORMATS"
fi
"$PNPM" --dir "$UPSTREAM/apps/desktop" run "$SCRIPT"
echo "==> 完成，产物见 $UPSTREAM/apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts"
