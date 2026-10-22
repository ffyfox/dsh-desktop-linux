# AGENTS.md

本仓库是 DeepSeek Harness 桌面端的 Linux 打包工程，不含应用源码：上游代码由
`scripts/fetch-upstream.sh` 取到 `upstream/`（不入库），这里只放补丁、PKGBUILD 和脚本。

## 硬规则

- 改代码或文档前先把方案给维护者过目；不要自行 push、打 tag 或改 GitHub release。
- [README.md](README.md) 只写重点、不写过程；与 [README.en.md](README.en.md) 必须同步修改。

## 回家读

- 补丁系列的编号、每块在解决什么、有哪些约束：[patches/README.md](patches/README.md)
- 用户可见行为、支持矩阵、构建方式：[README.md](README.md)

## 动手前先知道

- 每个补丁都是相对 [PKGBUILD](PKGBUILD) 里 `_tag` 那个 commit 的 diff；改 `_tag` 就要同步重做补丁，
  否则 `scripts/apply-patches.sh` 直接失败。
- [pkgbuild/](pkgbuild/) 是 `scripts/pkgbuild-dir.sh` 生成的可直接 `makepkg` 的摊平目录
  （makepkg 只在同目录按 basename 找本地 source），不要手改；改了根 PKGBUILD 就重新生成。
- 构建与验证都走 `scripts/`：`fetch-upstream.sh`、`apply-patches.sh`、`build.sh`、`verify.sh`。
  隔离数据目录用 `DSH_DESKTOP_LINUX_HOME`（默认 `/tmp/dsh-desktop-test`），脚本刻意不继承 `DSH_HOME`。
- 结束应用用 `pkill -f '[d]eepseek-harness$'`；`pkill -x deepseek-harness` 打不中（comm 被截成 `deepseek-harnes`）。
