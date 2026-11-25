#!/usr/bin/env bash
# 轻量静态检查与上游补丁双路线校验。
#
#   ./scripts/check-static.sh                       # 离线静态检查（语法 / PKGBUILD / 补丁登记 / 文档 / Workflow / ShellCheck）
#   ./scripts/check-static.sh --with-upstream       # 在离线检查之外，追加上游双路线试打与远端源码包 sha256 校验
#   ./scripts/check-static.sh --upstream-only       # 仅运行上游双路线试打与源码包校验（供 CI 拆分步骤）
#   ./scripts/check-static.sh --require-shellcheck  # 缺少 shellcheck 时直接判失败（默认跳过）
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REPO_URL="${REPO_URL:-https://github.com/deepseek-ai/deepseek-harness.git}"

RUN_OFFLINE=1
RUN_UPSTREAM=0
REQUIRE_SHELLCHECK=0
seen_with_upstream=0
seen_upstream_only=0

usage() {
  cat <<'EOF'
用法：
  ./scripts/check-static.sh [选项]

选项：
  --with-upstream       除离线静态检查外，拉取（或复用）干净上游树做双路线试打，
                        并校验 PKGBUILD source[0] 远端源码包 sha256 与顶层目录名
  --upstream-only       仅运行上游双路线试打与源码包校验（供 CI 独立步骤调用）
  --require-shellcheck  缺少 shellcheck 时判失败（默认跳过）
  -h, --help            显示此帮助信息
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-upstream)
      seen_with_upstream=1
      RUN_UPSTREAM=1
      shift
      ;;
    --upstream-only)
      seen_upstream_only=1
      RUN_OFFLINE=0
      RUN_UPSTREAM=1
      shift
      ;;
    --require-shellcheck)
      REQUIRE_SHELLCHECK=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if (( seen_with_upstream && seen_upstream_only )); then
  echo "错误：--with-upstream 与 --upstream-only 不能同时使用" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d /tmp/dsh-check-static-XXXXXX)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

pass=0
fail=0
skipped=0
ok()   { echo "  [PASS] $1"; pass=$((pass+1)); }
bad()  { echo "  [FAIL] $1"; fail=$((fail+1)); }
skip() { echo "  [SKIP] $1"; skipped=$((skipped+1)); }
info() { echo "  [INFO] $1"; }

# 消费结构化输出（每行 `<PASS|FAIL|SKIP|INFO|HEAD>\t<消息>`），保持计数器累加在当前 shell。
consume_report() {
  local report_file="$1" tag msg
  while IFS=$'\t' read -r tag msg; do
    case "$tag" in
      HEAD) echo "$msg" ;;
      PASS) ok "$msg" ;;
      FAIL) bad "$msg" ;;
      SKIP) skip "$msg" ;;
      INFO) info "$msg" ;;
      "")   ;;
      *)    info "$tag $msg" ;;
    esac
  done < "$report_file"
}

# 读取 PKGBUILD 核心元数据到 NUL 分隔流，供多个检查复用。
read_pkgbuild_stream() {
  bash -c '
    set -euo pipefail
    source "$1" >/dev/null 2>&1
    printf "pkgname\t%s\0pkgver\t%s\0pkgrel\t%s\0_tag\t%s\0_commit\t%s\0_srcdirname\t%s\0install\t%s\0" \
      "${pkgname:-}" "${pkgver:-}" "${pkgrel:-}" "${_tag:-}" "${_commit:-}" "${_srcdirname:-}" "${install:-}"
    for x in "${depends[@]-}"; do printf "depends\t%s\0" "$x"; done
    for x in "${source[@]-}"; do printf "source\t%s\0" "$x"; done
    for x in "${sha256sums[@]-}"; do printf "sha256sums\t%s\0" "$x"; done
  ' _ "$ROOT/PKGBUILD"
}

check_shell_and_shellcheck() {
  echo "== 1. Shell 语法、权限与 ShellCheck =="
  shopt -s nullglob
  local scripts=("$ROOT"/scripts/*.sh)
  local targets=("$ROOT/PKGBUILD" "$ROOT/dsh-desktop-linux.install" "${scripts[@]}")
  local f rel err_out syntax_bad=0 perm_bad=0 shebang_bad=0

  if (( ${#scripts[@]} == 0 )); then
    bad "scripts/ 下没有找到任何 .sh 脚本"
    return
  fi

  for f in "${targets[@]}"; do
    rel="${f#"$ROOT"/}"
    if ! err_out="$(bash -n "$f" 2>&1)"; then
      bad "$rel 存在 bash 语法错误：${err_out//$'\n'/ | }"
      syntax_bad=1
    fi
  done
  if (( ! syntax_bad )); then
    ok "bash -n 语法检查通过（${#targets[@]} 个文件）"
  fi

  local first_line=""
  for f in "${scripts[@]}"; do
    rel="${f#"$ROOT"/}"
    if [[ ! -x "$f" ]]; then
      bad "$rel 缺少可执行权限（+x）"
      perm_bad=1
    fi
    IFS= read -r first_line < "$f" || first_line=""
    if [[ "$first_line" != '#!/usr/bin/env bash' ]]; then
      bad "$rel 首行 shebang 应为 #!/usr/bin/env bash（实际：${first_line:-空}）"
      shebang_bad=1
    fi
  done
  if (( ! perm_bad && ! shebang_bad )); then
    ok "scripts/*.sh 均具备 +x 权限与统一 shebang（${#scripts[@]} 个文件）"
  fi

  if command -v shellcheck >/dev/null 2>&1; then
    local sc_out sc_rc=0
    sc_out="$(cd "$ROOT" && shellcheck -S error -x scripts/*.sh 2>&1)" || sc_rc=$?
    if (( sc_rc == 0 )); then
      ok "shellcheck -S error 通过（${#scripts[@]} 个脚本）"
    else
      bad "shellcheck -S error 检查失败："
      printf '%s\n' "$sc_out" | head -n 40 | sed 's/^/         /'
    fi
  elif (( REQUIRE_SHELLCHECK )); then
    bad "系统未安装 shellcheck（已指定 --require-shellcheck）"
  else
    skip "系统未安装 shellcheck，跳过脚本静态分析"
  fi
}

check_offline_python() {
  local pkg_stream="$WORK_DIR/pkgbuild.nul"
  local report_file="$WORK_DIR/offline.report"
  if ! read_pkgbuild_stream > "$pkg_stream"; then
    bad "无法在干净 bash 子 shell 中 source PKGBUILD"
    return
  fi

  local py_rc=0
  python3 - "$ROOT" "$pkg_stream" > "$report_file" 2>"$WORK_DIR/offline.err" <<'PY' || py_rc=$?
import glob
import hashlib
import os
import re
import subprocess
import sys

root = sys.argv[1]
pkg_stream_path = sys.argv[2]

def emit(tag, msg):
    clean = str(msg).replace("\t", " ").replace("\n", " | ").strip()
    print(f"{tag}\t{clean}")

raw_items = open(pkg_stream_path, "rb").read().split(b"\0")
scalars = {}
depends = []
sources = []
sha256sums = []
for item in raw_items:
    if not item:
        continue
    k, v = item.decode("utf-8", errors="replace").split("\t", 1)
    if k == "depends":
        depends.append(v)
    elif k == "source":
        sources.append(v)
    elif k == "sha256sums":
        sha256sums.append(v)
    else:
        scalars[k] = v

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fp:
        for chunk in iter(lambda: fp.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def parse_apply_patches_assets():
    txt = open(os.path.join(root, "scripts", "apply-patches.sh"), encoding="utf-8").read()
    m = re.search(r"^ASSETS=\(\s*(.*?)\s*^\)", txt, re.M | re.S)
    if not m:
        return None
    entries = []
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m_entry = re.match(r"""^(['"])([^'"]+)\1$""", line)
        if not m_entry or ":" not in m_entry.group(2):
            return None
        src, dst = m_entry.group(2).split(":", 1)
        entries.append((src, dst))
    return entries

# == 2. PKGBUILD 元数据与校验和 ==
print("HEAD\t== 2. PKGBUILD 元数据与 source/sha256sums ==")

meta_errors = []
pkgname = scalars.get("pkgname", "")
pkgver = scalars.get("pkgver", "")
pkgrel = scalars.get("pkgrel", "")
_tag = scalars.get("_tag", "")
_commit = scalars.get("_commit", "")
_srcdirname = scalars.get("_srcdirname", "")
install_file = scalars.get("install", "")

if not re.match(r"^[a-z0-9@._+-]+$", pkgname):
    meta_errors.append(f"pkgname 非法：{pkgname!r}")
if not re.match(r"^dsh-v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$", _tag):
    meta_errors.append(f"_tag 格式不符合约定：{_tag!r}")
else:
    expected_pkgver = re.sub(r"-(alpha|beta|rc)\.", r"\1", _tag[len("dsh-v"):])
    if pkgver != expected_pkgver:
        meta_errors.append(f"pkgver ({pkgver!r}) 与 _tag ({_tag!r}) 推导值 {expected_pkgver!r} 不一致")
if not re.match(r"^[1-9][0-9]*$", pkgrel):
    meta_errors.append(f"pkgrel 应为正整数：{pkgrel!r}")
if not re.match(r"^[0-9a-f]{40}$", _commit):
    meta_errors.append(f"_commit 应为 40 位小写 hex：{_commit!r}")
if _srcdirname != f"deepseek-harness-{_tag}":
    meta_errors.append(f"_srcdirname ({_srcdirname!r}) 应为 {f'deepseek-harness-{_tag}'!r}")
if not install_file or not os.path.isfile(os.path.join(root, install_file)):
    meta_errors.append(f"install 文件缺失：{install_file!r}")
if any(d == "libxss" or d.startswith(("libxss=", "libxss>", "libxss<")) for d in depends):
    meta_errors.append("depends 中不允许包含 libxss")

if meta_errors:
    for err in meta_errors:
        emit("FAIL", f"PKGBUILD 元数据：{err}")
else:
    emit("PASS", f"PKGBUILD 元数据与版本推导一致（{pkgname} {pkgver}-{pkgrel}，{_tag} @ {_commit[:8]}）")

# source 与 sha256sums
src_errors = []
if not sources or len(sources) != len(sha256sums):
    src_errors.append(f"source ({len(sources)}) 与 sha256sums ({len(sha256sums)}) 数量不匹配或为空")

for idx, digest in enumerate(sha256sums):
    if not re.match(r"^[0-9a-f]{64}$", digest):
        src_errors.append(f"sha256sums[{idx}] 不是 64 位小写 hex（禁止 SKIP）：{digest!r}")

disk_patches = sorted(os.path.basename(p) for p in glob.glob(os.path.join(root, "patches", "*.patch")))
pkg_patches = []
pkg_assets = []

if sources:
    s0 = sources[0]
    url0 = s0.split("::", 1)[1] if "::" in s0 else s0
    expected_suffix = f"/archive/refs/tags/{_tag}.tar.gz"
    if not (url0.startswith("https://") and url0.endswith(expected_suffix)):
        src_errors.append(f"source[0] URL 应以 {expected_suffix} 结尾：{url0!r}")

    for idx, entry in enumerate(sources[1:], start=1):
        if "://" in entry or "::" in entry or "/" in entry:
            src_errors.append(f"source[{idx}] 应为平铺本地文件名：{entry!r}")
            continue
        if entry.endswith(".patch"):
            pkg_patches.append(entry)
            fpath = os.path.join(root, "patches", entry)
        else:
            pkg_assets.append(entry)
            fpath = os.path.join(root, "assets", entry)
        if not os.path.isfile(fpath):
            src_errors.append(f"source[{idx}] 对应本地文件缺失：{os.path.relpath(fpath, root)}")
        elif idx < len(sha256sums) and re.match(r"^[0-9a-f]{64}$", sha256sums[idx]):
            actual = sha256_file(fpath)
            if actual != sha256sums[idx]:
                src_errors.append(f"sha256 不一致：{entry} 期望 {sha256sums[idx]} 实际 {actual}")

if pkg_patches != disk_patches:
    missing_in_pkg = [p for p in disk_patches if p not in pkg_patches]
    extra_in_pkg = [p for p in pkg_patches if p not in disk_patches]
    if missing_in_pkg or extra_in_pkg:
        src_errors.append(f"PKGBUILD 补丁清单与 patches/ 不一致（漏列={missing_in_pkg}, 多余={extra_in_pkg}）")
    else:
        src_errors.append("PKGBUILD 补丁顺序与 patches/ 排序顺序不一致")

assets_entries = parse_apply_patches_assets()
if assets_entries is None:
    src_errors.append("无法解析 scripts/apply-patches.sh 中的 ASSETS 数组")
else:
    declared_asset_names = []
    for src_rel, _ in assets_entries:
        src_abs = os.path.join(root, src_rel)
        if not os.path.isfile(src_abs):
            src_errors.append(f"apply-patches.sh ASSETS 源文件缺失：{src_rel}")
        declared_asset_names.append(os.path.basename(src_rel))
    if sorted(pkg_assets) != sorted(declared_asset_names):
        src_errors.append(f"PKGBUILD 本地资产 {pkg_assets} 与 apply-patches.sh ASSETS {declared_asset_names} 不一致")

if src_errors:
    for err in src_errors:
        emit("FAIL", f"PKGBUILD source/sha256：{err}")
else:
    emit("PASS", f"PKGBUILD source 与 sha256sums 强一致（1 源码包 + {len(pkg_patches)} 补丁 + {len(pkg_assets)} 资产）")

# == 3. 补丁系列规范与跨文件登记 ==
print("HEAD\t== 3. 补丁系列、verify.sh 与 patches/README.md 一致性 ==")

patch_errors = []
seen_ids = {}
patch_ids = []
for pname in disk_patches:
    m_name = re.match(r"^([0-9]{4})-[a-z0-9-]+\.patch$", pname)
    if not m_name:
        patch_errors.append(f"补丁文件名格式不规范：{pname}")
        continue
    pid = m_name.group(1)
    if pid in ("0014", "0015"):
        patch_errors.append(f"不得复用已作废的空号 {pid}：{pname}")
    if pid in seen_ids:
        patch_errors.append(f"补丁编号重复 {pid}：{seen_ids[pid]} 与 {pname}")
    seen_ids[pid] = pname
    patch_ids.append(pid)

    ptxt = open(os.path.join(root, "patches", pname), encoding="utf-8", errors="replace").read()
    if not ptxt.strip():
        patch_errors.append(f"补丁文件为空：{pname}")
    elif not (re.search(r"^diff --git ", ptxt, re.M) and re.search(r"^\+\+\+ ", ptxt, re.M)):
        patch_errors.append(f"补丁缺少标准 diff 头：{pname}")
    if "GIT binary patch" in ptxt:
        patch_errors.append(f"禁止出现 GIT binary patch（GNU patch 不支持）：{pname}")

verify_txt = open(os.path.join(root, "scripts", "verify.sh"), encoding="utf-8").read()
m_cov = re.search(r"declare -A PATCH_COVERAGE=\(\s*(.*?)\s*\)", verify_txt, re.S)
if not m_cov:
    patch_errors.append("scripts/verify.sh 中找不到 PATCH_COVERAGE 声明")
else:
    cov_body = re.sub(r"#.*$", "", m_cov.group(1), flags=re.M)
    entries = re.findall(r"\[(\d{4})\]=([A-Za-z0-9_-]+)", cov_body)
    leftover = re.sub(r"\[\d{4}\]=[A-Za-z0-9_-]+", "", cov_body).strip()
    if leftover:
        patch_errors.append(f"PATCH_COVERAGE 存在未识别项：{leftover!r}")
    cov_map = dict(entries)
    bad_vals = {k: v for k, v in cov_map.items() if v not in {"verify", "tests", "matrix", "pending"}}
    if bad_vals:
        patch_errors.append(f"PATCH_COVERAGE 存在非法覆盖级别：{bad_vals}")
    if len(entries) != len(cov_map):
        patch_errors.append("PATCH_COVERAGE 存在重复编号键")
    missing_cov = sorted(set(patch_ids) - set(cov_map))
    extra_cov = sorted(set(cov_map) - set(patch_ids))
    if missing_cov:
        patch_errors.append(f"patches/ 新增补丁尚未在 verify.sh PATCH_COVERAGE 登记：{missing_cov}")
    if extra_cov:
        patch_errors.append(f"verify.sh PATCH_COVERAGE 存在无对应文件的冗余编号：{extra_cov}")

patches_readme = open(os.path.join(root, "patches", "README.md"), encoding="utf-8").read()
missing_readme_patches = [p for p in disk_patches if p not in patches_readme]
if missing_readme_patches:
    patch_errors.append(f"patches/README.md 漏记补丁文件名：{missing_readme_patches}")

m_base = re.search(r"全部相对上游 `([0-9a-f]{7,40})`（tag `([^`]+)`）", patches_readme)
if not m_base:
    patch_errors.append("patches/README.md 开头找不到「全部相对上游 `<sha>`（tag `<tag>`）」基线声明")
else:
    short_sha, readme_tag = m_base.groups()
    if readme_tag != _tag:
        patch_errors.append(f"patches/README.md 基线 tag ({readme_tag!r}) 与 PKGBUILD _tag ({_tag!r}) 不一致")
    if not _commit.startswith(short_sha):
        patch_errors.append(f"patches/README.md 基线提交 ({short_sha!r}) 不是 PKGBUILD _commit ({_commit!r}) 前缀")

if patch_errors:
    for err in patch_errors:
        emit("FAIL", err)
else:
    emit("PASS", f"补丁命名、文本 diff 约束、verify.sh PATCH_COVERAGE 与 patches/README.md 基线完全一致（{len(disk_patches)} 个补丁）")

# == 4. 双语 README 标题结构与 Markdown 本地链接 ==
print("HEAD\t== 4. 双语 README 标题与 Markdown 本地链接 ==")

def iter_non_code_lines(path):
    fence_char = None
    fence_len = 0
    with open(path, encoding="utf-8") as fp:
        for lineno, line in enumerate(fp, 1):
            stripped = line.lstrip()
            if fence_char is None:
                m_open = re.match(r"^(`{3,}|~{3,})", stripped)
                if m_open:
                    fence_char = m_open.group(1)[0]
                    fence_len = len(m_open.group(1))
                    continue
                yield lineno, line
            else:
                m_close = re.match(rf"^({re.escape(fence_char)}{{{fence_len},}})\s*$", stripped)
                if m_close:
                    fence_char = None
                    fence_len = 0

def extract_headings(path):
    out = []
    for lineno, line in iter_non_code_lines(path):
        m = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if m:
            out.append((lineno, len(m.group(1)), m.group(2)))
    return out

zh_headings = extract_headings(os.path.join(root, "README.md"))
en_headings = extract_headings(os.path.join(root, "README.en.md"))
zh_levels = [lvl for _, lvl, _ in zh_headings]
en_levels = [lvl for _, lvl, _ in en_headings]
if zh_levels == en_levels and len(zh_headings) > 0:
    emit("PASS", f"中英 README 标题数量与层级序列逐项一致（{len(zh_headings)}:{len(en_headings)}）")
else:
    emit("FAIL", f"中英 README 标题数量或层级不一致（README.md={len(zh_headings)} {zh_levels}, README.en.md={len(en_headings)} {en_levels}）")

md_files = ["README.md", "README.en.md", "CONTRIBUTING.md", "AGENTS.md", "patches/README.md"]
link_errors = []
link_count = 0
for rel_md in md_files:
    abs_md = os.path.join(root, rel_md)
    base_dir = os.path.dirname(rel_md) or "."
    for lineno, line in iter_non_code_lines(abs_md):
        clean_line = re.sub(r"`+[^`]*`+", "", line)
        targets = re.findall(r"""\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)""", clean_line)
        targets += re.findall(r"""<img\b[^>]*\bsrc=['"]([^'"]+)['"]""", clean_line)
        for target in targets:
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            path_only = target.split("#", 1)[0].split("?", 1)[0]
            if not path_only:
                continue
            link_count += 1
            resolved = os.path.normpath(os.path.join(base_dir, path_only))
            if (rel_md, resolved) == ("AGENTS.md", "pkgbuild"):
                continue
            if resolved.startswith(".."):
                link_errors.append(f"{rel_md}:{lineno} 链接越出仓库根：{target!r}")
                continue
            abs_target = os.path.join(root, resolved)
            if not os.path.exists(abs_target):
                link_errors.append(f"{rel_md}:{lineno} 本地链接目标不存在：{target!r} -> {resolved}")
                continue
            ign = subprocess.run(["git", "-C", root, "check-ignore", "-q", "--", resolved], capture_output=True)
            if ign.returncode == 0:
                link_errors.append(f"{rel_md}:{lineno} 本地链接指向了被 .gitignore 忽略的路径：{target!r} -> {resolved}")

if link_errors:
    for err in link_errors:
        emit("FAIL", err)
else:
    emit("PASS", f"文档本地链接与图片目标检查通过（{len(md_files)} 份文档共 {link_count} 处相对链接）")

# == 5. GitHub Workflow / Dependabot YAML 与 Action SHA 锁定 ==
print("HEAD\t== 5. GitHub Workflow / Dependabot YAML 与 Action SHA 锁定 ==")

wf_files = sorted(
    glob.glob(os.path.join(root, ".github", "workflows", "*.yml"))
    + glob.glob(os.path.join(root, ".github", "workflows", "*.yaml"))
)
if not wf_files:
    emit("FAIL", ".github/workflows/ 下没有找到 workflow 文件")
else:
    try:
        import yaml
    except ImportError:
        emit("FAIL", "缺少 PyYAML（python3 无法 import yaml），请安装 python-yaml / python3-yaml")
    else:
        wf_errors = []
        pinned_count = 0

        def collect_uses(node, path):
            out = []
            if isinstance(node, dict):
                for k, v in node.items():
                    if k == "uses":
                        out.append((f"{path}.uses", v))
                    else:
                        out.extend(collect_uses(v, f"{path}.{k}"))
            elif isinstance(node, list):
                for i, item in enumerate(node):
                    out.extend(collect_uses(item, f"{path}[{i}]"))
            return out

        for wf in wf_files:
            rel_wf = os.path.relpath(wf, root)
            try:
                doc = yaml.safe_load(open(wf, encoding="utf-8"))
            except yaml.YAMLError as exc:
                wf_errors.append(f"{rel_wf} YAML 解析失败：{exc}")
                continue
            if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
                wf_errors.append(f"{rel_wf} 缺少有效的顶层 jobs 映射")
                continue
            for loc, val in collect_uses(doc.get("jobs"), "jobs"):
                if not isinstance(val, str):
                    wf_errors.append(f"{rel_wf} ({loc}) uses 非字符串：{val!r}")
                    continue
                if val.startswith("./"):
                    continue
                if not re.match(r"^[^@\s]+@[0-9a-f]{40}$", val):
                    wf_errors.append(f"{rel_wf} ({loc}) 未锁定为 40 位 commit SHA：{val!r}")
                else:
                    pinned_count += 1

        if wf_errors:
            for err in wf_errors:
                emit("FAIL", err)
        else:
            emit("PASS", f"全部 Workflow YAML 语法有效，且 {pinned_count} 处外部 Action 均锁定 40 位 SHA（{len(wf_files)} 个文件）")

        dep_yml = os.path.join(root, ".github", "dependabot.yml")
        dep_yaml = os.path.join(root, ".github", "dependabot.yaml")
        has_yml = os.path.isfile(dep_yml)
        has_yaml = os.path.isfile(dep_yaml)
        dep_errors = []
        dep_updates = []
        if has_yml and has_yaml:
            dep_errors.append("同时存在 .github/dependabot.yml 与 .github/dependabot.yaml")
        elif not has_yml and not has_yaml:
            dep_errors.append(".github/dependabot.yml 缺失")
        elif has_yaml:
            dep_errors.append("请统一命名为 .github/dependabot.yml（当前为 .github/dependabot.yaml）")
        else:
            try:
                dep_doc = yaml.safe_load(open(dep_yml, encoding="utf-8"))
            except yaml.YAMLError as exc:
                dep_errors.append(f".github/dependabot.yml YAML 解析失败：{exc}")
            else:
                if not isinstance(dep_doc, dict) or dep_doc.get("version") != 2:
                    dep_errors.append(".github/dependabot.yml 顶层必须包含 version: 2")
                updates = dep_doc.get("updates") if isinstance(dep_doc, dict) else None
                if not isinstance(updates, list) or len(updates) == 0:
                    dep_errors.append(".github/dependabot.yml 的 updates 必须为非空列表")
                else:
                    dep_updates = updates
                    for idx, item in enumerate(updates):
                        prefix = f".github/dependabot.yml updates[{idx}]"
                        if not isinstance(item, dict):
                            dep_errors.append(f"{prefix} 必须为映射")
                            continue
                        eco = item.get("package-ecosystem")
                        if not isinstance(eco, str) or not eco.strip():
                            dep_errors.append(f"{prefix} 缺少非空字符串 package-ecosystem")
                        directory = item.get("directory")
                        directories = item.get("directories")
                        has_dir = isinstance(directory, str) and bool(directory.strip())
                        has_dirs = (
                            isinstance(directories, list)
                            and len(directories) > 0
                            and all(isinstance(d, str) and bool(d.strip()) for d in directories)
                        )
                        if not (has_dir or has_dirs):
                            dep_errors.append(f"{prefix} 缺少有效 directory 或 directories")
                        sched = item.get("schedule")
                        if not isinstance(sched, dict) or not isinstance(sched.get("interval"), str) or not sched["interval"].strip():
                            dep_errors.append(f"{prefix}.schedule 缺少非空字符串 interval")
                        if "cooldown" in item:
                            cd = item.get("cooldown")
                            if not isinstance(cd, dict):
                                dep_errors.append(f"{prefix}.cooldown 必须为映射")
                            else:
                                for ck in ("default-days", "semver-major-days", "semver-minor-days", "semver-patch-days"):
                                    if ck in cd:
                                        cv = cd[ck]
                                        if isinstance(cv, bool) or not isinstance(cv, int) or cv <= 0:
                                            dep_errors.append(f"{prefix}.cooldown.{ck} 必须为正整数")
                        if "commit-message" in item and not isinstance(item.get("commit-message"), dict):
                            dep_errors.append(f"{prefix}.commit-message 必须为映射")

        if dep_errors:
            for err in dep_errors:
                emit("FAIL", err)
        else:
            emit("PASS", f".github/dependabot.yml 语法与 version: 2 基础结构有效（{len(dep_updates)} 项生态配置）")
PY

  if (( py_rc != 0 )); then
    bad "离线检查 Python 校验器异常退出（exit $py_rc）：$(tr '\n' ' ' < "$WORK_DIR/offline.err")"
    return
  fi
  consume_report "$report_file"
}

check_pkgbuild_dir_dry_run() {
  echo "== 6. pkgbuild-dir.sh 摊平演练 =="
  local dry="$WORK_DIR/pkgbuild-dry"
  local pkg_out
  if ! pkg_out="$("$ROOT/scripts/pkgbuild-dir.sh" "$dry" 2>&1)"; then
    bad "scripts/pkgbuild-dir.sh 执行失败：${pkg_out//$'\n'/ | }"
    return
  fi

  local dry_err=0 count=0
  if ! cmp -s "$ROOT/PKGBUILD" "$dry/PKGBUILD"; then
    bad "摊平目录中的 PKGBUILD 与仓库根不一致"
    dry_err=1
  fi

  local pkg_stream="$WORK_DIR/pkgbuild-dry.nul"
  read_pkgbuild_stream > "$pkg_stream"
  local tag val pkg_install=""
  local -a local_sources=()
  while IFS= read -r -d '' entry; do
    tag="${entry%%$'\t'*}"
    val="${entry#*$'\t'}"
    case "$tag" in
      install) pkg_install="$val" ;;
      source)
        if [[ "$val" != *'://'* && "$val" != *'::'* ]]; then
          local_sources+=("$val")
        fi
        ;;
    esac
  done < "$pkg_stream"

  if [[ -n "$pkg_install" ]]; then
    if [[ ! -f "$dry/$pkg_install" ]] || ! cmp -s "$ROOT/$pkg_install" "$dry/$pkg_install"; then
      bad "摊平目录中缺失或不一致的 install 脚本：$pkg_install"
      dry_err=1
    fi
  fi

  local s src_orig
  for s in "${local_sources[@]}"; do
    if [[ "$s" == *.patch ]]; then
      src_orig="$ROOT/patches/$s"
    else
      src_orig="$ROOT/assets/$s"
    fi
    if [[ ! -f "$dry/$s" ]] || ! cmp -s "$src_orig" "$dry/$s"; then
      bad "摊平目录中缺失或不一致的本地 source：$s"
      dry_err=1
    else
      count=$((count + 1))
    fi
  done

  if (( ! dry_err )); then
    ok "pkgbuild-dir.sh 摊平完整且与源文件逐字节一致（PKGBUILD + $pkg_install + $count 项本地 source）"
  fi
}

check_upstream_dual_route_and_tarball() {
  echo "== 7. 上游基线双路线试打与远端源码包校验 =="
  local pkg_stream="$WORK_DIR/upstream-pkg.nul"
  if ! read_pkgbuild_stream > "$pkg_stream"; then
    bad "无法读取 PKGBUILD 元数据"
    return
  fi

  local tag val pkg_tag="" pkg_commit="" pkg_srcdirname="" pkg_url="" pkg_sha256=""
  local -a pkg_patches=()
  while IFS= read -r -d '' entry; do
    tag="${entry%%$'\t'*}"
    val="${entry#*$'\t'}"
    case "$tag" in
      _tag) pkg_tag="$val" ;;
      _commit) pkg_commit="$val" ;;
      _srcdirname) pkg_srcdirname="$val" ;;
      source)
        if [[ -z "$pkg_url" ]]; then
          pkg_url="${val#*::}"
        elif [[ "$val" == *.patch ]]; then
          pkg_patches+=("$val")
        fi
        ;;
      sha256sums)
        if [[ -z "$pkg_sha256" ]]; then
          pkg_sha256="$val"
        fi
        ;;
    esac
  done < "$pkg_stream"

  local -a asset_pairs=()
  mapfile -t asset_pairs < <(python3 -c '
import os, re, sys
txt = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^ASSETS=\(\s*(.*?)\s*^\)", txt, re.M | re.S)
if not m:
    sys.exit(1)
for line in m.group(1).splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    m2 = re.match(r"^([\x27\"])([^\x27\"]+)\1$", line)
    if m2 and ":" in m2.group(2):
        print(m2.group(2))
' "$ROOT/scripts/apply-patches.sh") || {
    bad "无法解析 scripts/apply-patches.sh 中的 ASSETS"
    return
  }

  local w="$WORK_DIR/upstream"
  mkdir -p "$w"

  # 绝不修改仓库中现有的 ./upstream：若提交匹配则直接用只读 git archive，否则在临时目录浅克隆。
  local upstream_src="" local_head=""
  if [[ -d "$ROOT/upstream/.git" ]]; then
    local_head="$(git -C "$ROOT/upstream" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$local_head" == "$pkg_commit" ]]; then
      upstream_src="$ROOT/upstream"
      ok "复用本地 upstream HEAD（${pkg_commit:0:8}，只读 git archive 不改动工作树）"
    else
      info "本地 upstream HEAD (${local_head:-未知}) != PKGBUILD _commit (${pkg_commit:0:8})，改为临时目录克隆"
    fi
  fi

  if [[ -z "$upstream_src" ]]; then
    info "正在临时目录克隆 $pkg_tag..."
    local repo="$w/repo"
    if ! git clone --depth 1 --branch "$pkg_tag" -- "$UPSTREAM_REPO_URL" "$repo" >/dev/null 2>&1; then
      rm -rf "$repo"
      if ! git clone -- "$UPSTREAM_REPO_URL" "$repo" >/dev/null 2>&1 \
        || ! ( git -C "$repo" checkout --detach "$pkg_tag" >/dev/null 2>&1 \
            || git -C "$repo" checkout --detach "origin/$pkg_tag" >/dev/null 2>&1 ); then
        bad "临时克隆上游 $pkg_tag 失败"
        repo=""
      fi
    fi
    if [[ -n "$repo" ]]; then
      local cloned_head
      cloned_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
      if [[ "$cloned_head" == "$pkg_commit" ]]; then
        ok "临时克隆基线校验通过：$pkg_tag == ${pkg_commit:0:8}"
        upstream_src="$repo"
      else
        bad "上游 $pkg_tag 的 HEAD (${cloned_head:-空}) 与 PKGBUILD _commit ($pkg_commit) 不一致"
      fi
    fi
  fi

  if [[ -n "$upstream_src" ]]; then
    mkdir -p "$w/tree-git" "$w/tree-patch"
    if ! git -C "$upstream_src" archive HEAD | tar -xf - -C "$w/tree-git" \
      || ! git -C "$upstream_src" archive HEAD | tar -xf - -C "$w/tree-patch"; then
      bad "从 $upstream_src 解出干净上游树失败"
    else
      local git_apply_ok=1 gnu_patch_ok=1
      git -C "$w/tree-git" init -q

      shopt -s nullglob
      local disk_patches=("$ROOT"/patches/*.patch)
      local p err_msg=""
      for p in "${disk_patches[@]}"; do
        if ! err_msg="$(git -C "$w/tree-git" apply "$p" 2>&1)"; then
          bad "git apply 失败（$(basename "$p")）：${err_msg//$'\n'/ | }"
          git_apply_ok=0
          break
        fi
      done
      if (( git_apply_ok )); then
        ok "路线 1（git apply）按序应用全部 ${#disk_patches[@]} 个补丁成功"
      fi

      local pname
      for pname in "${pkg_patches[@]}"; do
        if ! err_msg="$(cd "$w/tree-patch" && patch -Np1 -i "$ROOT/patches/$pname" </dev/null 2>&1)"; then
          bad "GNU patch -Np1 失败（$pname）：${err_msg//$'\n'/ | }"
          gnu_patch_ok=0
          break
        fi
      done
      if (( gnu_patch_ok )); then
        ok "路线 2（patch -Np1）按 PKGBUILD 顺序应用全部 ${#pkg_patches[@]} 个补丁成功"
      fi

      local entry asset_src asset_dst
      for entry in "${asset_pairs[@]}"; do
        asset_src="${entry%%:*}"
        asset_dst="${entry#*:}"
        install -Dm644 "$ROOT/$asset_src" "$w/tree-git/$asset_dst"
        install -Dm644 "$ROOT/$asset_src" "$w/tree-patch/$asset_dst"
      done

      if (( git_apply_ok && gnu_patch_ok )); then
        local diff_file="$w/routes.diff"
        if diff -ru --exclude=.git --exclude='*.orig' "$w/tree-git" "$w/tree-patch" > "$diff_file"; then
          ok "双路线产物树逐字节一致（git apply == patch -Np1）"
        else
          bad "git apply 与 GNU patch -Np1 两条路线结果不一致："
          head -n 40 "$diff_file" | sed 's/^/         /'
        fi
      fi
    fi
  fi

  # B2：校核 PKGBUILD source[0] 远端源码包 sha256 与顶层目录名
  info "正在下载并校验源码包：$pkg_url"
  local tarball="$w/source.tar.gz"
  if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 120 "$pkg_url" -o "$tarball"; then
    bad "下载 PKGBUILD source[0] 源码包失败：$pkg_url"
    return
  fi

  local got_sha256
  got_sha256="$(sha256sum "$tarball" | awk '{print $1}')"
  if [[ "$got_sha256" == "$pkg_sha256" ]]; then
    ok "PKGBUILD source[0] 远端源码包 sha256 一致（${got_sha256:0:12}…）"
  else
    bad "PKGBUILD source[0] 源码包 sha256 不一致：期望 $pkg_sha256 实际 $got_sha256"
  fi

  local first_member
  if first_member="$(python3 -c '
import sys, tarfile
with tarfile.open(sys.argv[1], "r|gz") as tf:
    for m in tf:
        if m.name in ("pax_global_header", "."):
            continue
        print(m.name)
        break
' "$tarball" 2>&1)"; then
    if [[ -n "$first_member" ]] && [[ "$first_member" == "$pkg_srcdirname" || "$first_member" == "$pkg_srcdirname/"* ]]; then
      ok "源码包顶层目录与 _srcdirname 一致（$pkg_srcdirname）"
    else
      bad "源码包首个条目（${first_member:-空}）不匹配 _srcdirname（$pkg_srcdirname）"
    fi
  else
    bad "解析源码包 tar.gz 失败：$first_member"
  fi
}

if (( RUN_OFFLINE )); then
  check_shell_and_shellcheck
  check_offline_python
  check_pkgbuild_dir_dry_run
fi

if (( RUN_UPSTREAM )); then
  check_upstream_dual_route_and_tarball
fi

echo
echo "== 汇总：$pass 通过 / $fail 失败 / $skipped 跳过 =="
(( fail == 0 ))
