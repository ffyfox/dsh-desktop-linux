# AGENTS.md

本仓库是 DeepSeek Harness 桌面端的 Linux 打包工程，不含应用源码：上游代码由
`scripts/fetch-upstream.sh` 取到 `upstream/`（不入库），这里只放补丁、PKGBUILD 和脚本。

## 核心规则

- 改代码或文档前先把方案给维护者过目；不要自行 push、打 tag 或改 GitHub release。
- 常规变更（上游同步 `sync/v<上游版本号>`、补丁、构建/CI、新功能、复杂修复）统一从最新 `master` 切短期分支并走 PR；仅明显错别字、格式调整等极小低风险文档修正允许直接提交 `master`。严禁对 `master` 执行 force push；分支前缀与 PR 合并策略以 [CONTRIBUTING.md](CONTRIBUTING.md) 为准。
- [README.md](README.md) 只写重点，如非必要不写讨论、研究、决策或修改等过程；与 [README.en.md](README.en.md) 必须同步修改。

## 发版流程

从跟上游到发版走固定的 14 站（按 `AGENTS.local.md` 走）。两条必须守住：

- **不跨站**：一站做完、判据过了才进下一站；「继续」只表示做完当前这一步。
- **tag 铁律**：上游同步在 `sync/v<上游版本号>` 分支完成空跑 CI 与装机后再合并入 `master`，打 tag 前须核对 `master^{tree}` 与空跑 `headSha^{tree}` 一致（代码树逐字节相同），且 tag 绝不重打。

## 相关文档

- 补丁系列的编号、每块在解决什么、有哪些约束：[patches/README.md](patches/README.md)
- 用户可见行为、支持矩阵、构建方式：[README.md](README.md)
- 分支命名、PR 合并策略与收录边界：[CONTRIBUTING.md](CONTRIBUTING.md)

## 开发须知

- 每个补丁都是相对 [PKGBUILD](PKGBUILD) 里 `_tag` 那个 commit 的 diff；改 `_tag` 就要同步重做补丁，
  否则 `scripts/apply-patches.sh` 直接失败。
- [pkgbuild/](pkgbuild/) 是 `scripts/pkgbuild-dir.sh` 生成的可直接 `makepkg` 的摊平目录
  （makepkg 只在同目录按 basename 找本地 source），不要手改；改了根 PKGBUILD 就重新生成。
- 构建与验证都走 `scripts/`：`fetch-upstream.sh`、`apply-patches.sh`、`build.sh`、`verify.sh`。
  隔离数据目录用 `DSH_DESKTOP_LINUX_HOME`（默认 `/tmp/dsh-desktop-test`），脚本刻意不继承 `DSH_HOME`。
- 结束应用用 `pkill -f '[d]eepseek-harness$'`；`pkill -x deepseek-harness` 打不中（comm 被截成 `deepseek-harnes`）。
