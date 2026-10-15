# 参与贡献

感谢你愿意为 **DeepSeek Harness 桌面端 Linux 打包** 出一份力！无论是报告一个问题、
提个新想法，还是直接送代码过来，本项目都非常欢迎。

为了让大家协作起来更高效、也更愉快，动手前请花几分钟读一下这份指南。

## 这个仓库只做一件事

**把官方 DeepSeek Harness 桌面端（Electron）打包到 Linux。** 这里没有应用源码 ——
上游代码由 `scripts/fetch-upstream.sh` 取到 `upstream/`（不入库），仓库里只有补丁、
`PKGBUILD` 和脚本。

## 先读这两份

- [patches/README.md](patches/README.md)：补丁系列的编号、每块在解决什么、有哪些约束。
- [README.md](README.md)：用户可见行为、支持矩阵、构建方式。

## 提交 issue

- **先搜一下**：提交前建议先搜现有 issue，避免重复。
- **带上环境**：请尽量写清发行版与版本、桌面环境（X11 / Wayland）、包格式
  （AppImage / deb / rpm / Arch）、产物版本，以及能复现的最短步骤。
- **上游本身的缺陷请报给上游**：上游目前不收外部 PR、issue 也关着，只能走
  [GitHub Discussions](https://github.com/deepseek-ai/deepseek-harness/discussions)。
  本仓库只处理移植层的问题（打包、Linux 集成、Arch 包）。

## 提交 PR

- **分支名**：建议用 `fix/<短描述>`、`feature/<短描述>`、`chore/<短描述>`；一个 PR 只做
  一件事。
- **提交信息**：请用中文，标题带类型前缀（`fix` / `feat` / `docs` / `chore` / `build` / `ci` …），
  正文写清楚**为什么**这么改，而不是复述改了什么。
- **文档要成对**：改 `README.md` 时请同步改 `README.en.md`，两份是对照的。
- **改补丁前先看组织约定**：[patches/README.md](patches/README.md) 开头那条要求
  **一条改动只属于一个补丁**；一个文件可以被多个补丁触及，这时要按「基线 + 只有这一个
  补丁」的隔离树取 diff。这样每个补丁的职责都能单独说清。
- **动了 `PKGBUILD` 里的 `_tag`，受影响的那批补丁就要重做**，否则
  `scripts/apply-patches.sh` 会直接失败。

## 本地怎么验证

```sh
./scripts/fetch-upstream.sh          # 取上游（默认用 PKGBUILD 里的 _tag）
./scripts/apply-patches.sh           # 打补丁 + 把托盘 PNG 放进源码树
pnpm install --frozen-lockfile       # 在 upstream/ 里跑
./scripts/build.sh --all             # AppImage + deb + rpm
./scripts/verify.sh                  # 静态检查 + 活体矩阵
```

- **数据目录是隔离的**：用 `DSH_DESKTOP_LINUX_HOME`（默认 `/tmp/dsh-desktop-test`）。
  脚本**刻意不继承** `DSH_HOME`：DSH 会话会把它指向你真实的 `~/.dsh`。
- **结束应用**请用 `pkill -f '[d]eepseek-harness$'`；`pkill -x deepseek-harness` 打不中
  （进程名被截成 `deepseek-harnes`）。
- **依赖**：打 rpm 的机器要有 `rpmbuild`；跑 AppImage 要有 `libfuse.so.2`。
  deb 不需要额外工具。
- **改了上游源码行为，建议把对应的上游 spec 一起改掉，就改在同一个补丁里。** 补丁全部应用
  之后，上游自己的桌面单测应该是零失败；如果它红了，可以先看看是不是这次改行为时漏掉了
  对应的 spec。
- **想跑这套单测**，在 `upstream/` 里执行
  `/usr/bin/pnpm exec vitest run apps/desktop/tests apps/desktop-host/tests`。
  两点提醒：这里用 `/usr/bin/pnpm`（本机 `~/.npm-global/bin/pnpm` 是 9.15.4，会把它遮住）；
  跑之前把代理环境变量摘掉，否则连 `127.0.0.1` 也会走代理、多出几个失败。更细的说明在
  [patches/README.md](patches/README.md) 的「注意」里。`scripts/` 与 CI 都不跑它，需要时
  手动跑一次即可。

## 合并方式

- 单提交的 PR：**Rebase and merge**。
- 多提交的 PR：麻烦你先自己 squash 成一个提交；不方便的话，维护者会用 **Squash and merge**。
- 本仓库**不使用 merge commit**，也**不会改写你已经推送过的分支** ——
  需要修正时，我会在你的分支上追加提交，最后 squash 合入。

## 许可

本仓库以 [MIT](LICENSE) 发布；提交 PR 即表示你同意你的贡献也按该许可分发。
