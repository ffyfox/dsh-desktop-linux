#!/usr/bin/env bash
# 由 build.sh / dev-desktop.sh `source`：挑一个能用的 pnpm 11，结果放进 $PNPM。
#
# 两个条件（缺一不可）：
#   1. 版本是 11.x —— 上游 packageManager 钉的是 pnpm@11.28.5；
#   2. 它交给脚本的 npm_execpath 能被 node 执行。
#
# 第 2 条来自上游 desktop 脚本的硬性写法：package-target.ts / flock-entry.ts / dev.ts 三处是
# 无条件 `node $npm_execpath`（见 patches/README.md 的「注意」）。官方 standalone 安装器与
# Homebrew 给的是编译好的二进制，那种 pnpm 交给脚本的入口就是二进制本身，`node` 解析它会报
# `SyntaxError: Invalid or unexpected token` —— 用同一个表达式提前探一次，命中就退到隔离版，
# 免得构建跑到打包阶段才以一种看不懂的方式失败。
#
# 用法：source "$ROOT/scripts/select-pnpm.sh"   # 设置 $PNPM；都不合用则报到 stderr 后 exit 1

# 复刻上游那三处的调用方式：在钉了同一个 packageManager 的临时工程里跑一个脚本，
# 让脚本自己执行 `node $npm_execpath --version`（上游就是这么炸的）。
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

_dsh_pnpm_fallback="$HOME/.local/share/dsh-pnpm-11/node_modules/.bin/pnpm"

_dsh_pnpm_hint() {
  echo "==> 需要 pnpm 11.x，并且它的入口要能被 node 执行（用 npm 或 corepack 安装；" >&2
  echo "    官方 standalone 安装器与 Homebrew 给的是二进制，不行）。安装隔离版：" >&2
  echo "    npm i --prefix ~/.local/share/dsh-pnpm-11 pnpm@11.28.5" >&2
}

PNPM="$(command -v pnpm || true)"
_dsh_why=""

if [[ -n "$PNPM" && -x "$PNPM" ]]; then
  _dsh_version="$("$PNPM" --version 2>/dev/null || true)"
  if [[ "$_dsh_version" != 11.* ]]; then
    _dsh_why="版本不是 11.x（$_dsh_version）"
  elif ! _dsh_pnpm_entry_runs_under_node "$PNPM"; then
    _dsh_why="它交给脚本的入口不能被 node 执行（上游三处是 \`node \$npm_execpath\`；多半是官方 standalone 安装器或 Homebrew 装的二进制）"
  fi
else
  PNPM=""
  _dsh_why="系统里没有 pnpm"
fi

if [[ -z "$_dsh_why" ]]; then
  : # 系统 pnpm 可用，保持不动
else
  echo "==> 系统的 pnpm 不合用：$_dsh_why"
  if _dsh_pnpm_usable "$_dsh_pnpm_fallback"; then
    PNPM="$_dsh_pnpm_fallback"
    echo "==> 改用隔离版 pnpm：$PNPM ($("$PNPM" --version))"
  else
    _dsh_pnpm_hint
    exit 1
  fi
fi
