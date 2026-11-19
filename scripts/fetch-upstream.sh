#!/usr/bin/env bash
# clone + checkout 上游 monorepo 到 ./upstream
#
#   ./scripts/fetch-upstream.sh                     # PKGBUILD 里的 _tag，--depth 1，并校验 _commit
#   ./scripts/fetch-upstream.sh master              # 指定分支（不校验 _commit）
#   ./scripts/fetch-upstream.sh v0.2.0-rc.1         # 指定 tag
#   ./scripts/fetch-upstream.sh --commit <sha> <ref>  # 指定 ref 并校验 HEAD == <sha>
#   REFRESH=1 ./scripts/fetch-upstream.sh           # 已存在则重新拉取
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/deepseek-ai/deepseek-harness.git}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/upstream"

REF=""
EXPECTED_COMMIT=""
HAS_COMMIT_ARG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit)
      [[ $# -ge 2 ]] || { echo "错误：--commit 缺少参数" >&2; exit 2; }
      EXPECTED_COMMIT="$2"
      HAS_COMMIT_ARG=1
      shift 2
      ;;
    --commit=*)
      EXPECTED_COMMIT="${1#*=}"
      HAS_COMMIT_ARG=1
      shift
      ;;
    -*)
      echo "未知参数：$1" >&2
      exit 2
      ;;
    *)
      if [[ -n "$REF" ]]; then
        echo "多余的参数：$1（已指定 ref=$REF）" >&2
        exit 2
      fi
      REF="$1"
      shift
      ;;
  esac
done

mapfile -t _pkg_vals < <(bash -c 'source "$1"; printf "%s\n%s\n" "${_tag:-}" "${_commit:-}"' _ "$ROOT/PKGBUILD" 2>/dev/null || true)
PKG_TAG="${_pkg_vals[0]:-}"
PKG_COMMIT="${_pkg_vals[1]:-}"

# patches/ 里每个 diff 都是相对 PKGBUILD 里 _tag 那个 commit 的，对着 master 打补丁会直接
# 失败。默认取 _tag 而不是 master，与 CI 用同一个真源，不在这里再写死一遍。
if [[ -z "$REF" ]]; then
  REF="$PKG_TAG"
  if [[ -z "$REF" ]]; then
    echo "从 PKGBUILD 读不到 _tag；请显式传入 ref，例如：$0 master" >&2
    exit 1
  fi
fi

# 未显式传 --commit 时，只要拉的就是 PKGBUILD 锁定的 _tag，就自动用 _commit 兜底校验，
# 防止上游 tag 被悄悄移动。
if (( HAS_COMMIT_ARG == 0 )) && [[ -n "$PKG_TAG" && "$REF" == "$PKG_TAG" ]]; then
  EXPECTED_COMMIT="$PKG_COMMIT"
fi

if [[ ! "$REF" =~ ^[A-Za-z0-9._/@+-]+$ || "$REF" == -* || "$REF" == *..* ]]; then
  echo "非法上游 ref：$REF" >&2
  exit 1
fi

if [[ -n "$EXPECTED_COMMIT" && ! "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "期望的 commit SHA 格式非法：'$EXPECTED_COMMIT'" >&2
  exit 1
fi

verify_head_commit() {
  [[ -n "$EXPECTED_COMMIT" ]] || return 0
  local actual
  actual="$(git -C "$DEST" rev-parse HEAD)"
  if [[ "$actual" != "$EXPECTED_COMMIT" ]]; then
    echo "错误：$DEST 的 HEAD ($actual) 与期望提交 ($EXPECTED_COMMIT) 不一致（ref=$REF）" >&2
    return 1
  fi
  echo "==> commit 校验通过：$actual"
}

if [[ -d "$DEST/.git" ]]; then
  if [[ "${REFRESH:-0}" == "1" ]]; then
    echo "==> 已存在 $DEST，REFRESH=1，重新拉取 $REF"
    rm -rf "$DEST"
  else
    echo "==> $DEST 已存在，跳过（要重拉用 REFRESH=1）"
    git -C "$DEST" log --oneline -1
    if ! verify_head_commit; then
      echo "提示：本地 $DEST 可能停在旧版本，重拉请运行 REFRESH=1 $0" >&2
      exit 1
    fi
    exit 0
  fi
fi

echo "==> clone $REPO_URL @ $REF"
# 默认浅克隆；指定 tag 时也先浅克隆，失败再回退全量
if ! git clone --depth 1 --branch "$REF" -- "$REPO_URL" "$DEST" 2>/dev/null; then
  echo "==> 浅克隆 $REF 失败（可能是非分支 ref），回退全量克隆"
  rm -rf "$DEST"
  git clone -- "$REPO_URL" "$DEST"
  git -C "$DEST" checkout --detach "$REF" 2>/dev/null || git -C "$DEST" checkout --detach "origin/$REF"
fi

verify_head_commit

echo "==> 完成"
git -C "$DEST" log --oneline -1
echo "==> 磁盘占用：$(du -sh "$DEST" | cut -f1)"
