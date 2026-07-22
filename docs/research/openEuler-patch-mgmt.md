# openEuler Patch 管理调研报告

> 调研日期:2026-07-22
> 样本:`gitcode.com/src-openeuler/redis`(非内核普通包)+ `gitcode.com/src-openeuler/kernel`(内核包)
> 对比对象:`boostkit-patches-governance-demo` v5.4(本仓)

## 1. 背景与样本选择

openEuler 是 OpenAtom 基金会托管的 Linux 发行版社区。其 patch 管理有**两套并存的机制**,取决于包类型:

| 包类型 | 样本 | 主导机制 |
|---|---|---|
| 普通包(src-openeuler/redis 等)| gitcode.com/src-openeuler/redis | RPM `.spec` 文件 + `Patch00XX` + `%autopatch` |
| 内核包(src-openeuler/kernel) | gitcode.com/src-openeuler/kernel | `apply-patches` shell 脚本 + `guards` Perl + `series.conf`(继承自 SUSE)|

**两套机制共存,openEuler 自己也未统一**。

## 2. 目录结构

### 2.1 普通包(`src-openeuler/redis` master 分支)

```
src-openeuler/redis/
├── .spec                        # 必填,RPM 构建规范
├── .yaml                        # CI 配置
├── 0001-...patch                # 4 位序号 + 描述,直接在仓库根
├── 0002-...patch                # 顺序号即应用顺序
├── redis-conf.patch             # 无序号但按字母序在 spec 里引用
├── <name>-<version>.tar.gz      # 上游源码包
├── macros.<name>                # RPM 宏定义
├── <name>.service / .sysusers / .tmpfiles / .logrotate   # 系统集成文件
├── README.md
└── LICENSE                      # 上游 LICENSE
```

**关键观察**:
- **没有** `.patches/` 子目录
- **没有** 单独的 `series` 文件
- patch 全部在仓库**根目录扁平**摆放
- 4 位序号 `0001-` 是 RPM 生态惯用,顺序由 `.spec` 中 `Patch00XX:` 行的出现次序控制

### 2.2 内核包(`src-openeuler/kernel` openEuler-24.03-LTS)

```
src-openeuler/kernel/
├── kernel.spec                  # 主 spec
├── kernel-rt.spec / haoc-kernel.spec / raspberrypi-kernel.spec  # 变体 spec
├── apply-patches                # ★ 核心:SUSE-origin shell 脚本
├── guards                       # ★ 核心:SUSE-origin Perl 脚本
├── check-kabi                   # KABI 校验
├── kabi_whitelist_aarch64       # 架构特定 KABI 白名单
├── Module.kabi_aarch64 / Module.kabi_x86_64
├── 0000-raspberrypi-kernel.patch
├── 0001-riscv-kernel.patch
├── 0001-raspberrypi-kernel-RT.patch
├── 0002-...                     # 变体补丁 4 位序号,但**与 main series 独立计数**
├── patch-6.6.0-6.0.0-rt20.patch # 大版本合并 patch(quilt 风格)
├── patch-6.6.0-6.0.0-rt20.patch-openeuler_defconfig.patch  # 配套 config
└── (其他构建辅助文件)
```

**关键观察**:
- 内核包**也有根目录扁平 patch**(沿用 RPM 生态)
- 但**额外**有 `apply-patches` + `guards` 子系统(来自 SUSE,见 §3.2)
- spec 变体多(kernel / kernel-rt / haoc / raspberrypi),每个 spec 引用不同 patch 子集

### 2.3 `patches.kernel.org/series` 风格(内核衍生)

`apply-patches` 脚本默认期望的输入:

```text
# patches.kernel.org/series  示例(伪)
patches.kernel.org/0001-ipv4-fix-null-deref.patch
+CONFIG_X86 patches.kernel.org/0002-x86-only-fix.patch
-CONFIG_RT  patches.kernel.org/0003-rt-exclude.patch
patches.kernel.org/0004-shared-fix.patch
```

每行 = `path/<filename>`,行内 `+SYMBOL` / `-SYMBOL` 是 guard(条件包含/排除)。`guards` 脚本根据传入 symbol 决定是否应用。

`patches.addon/series` 是**附加层**:同一脚本支持 `apply-patches <series> <patchdir> <symbol...>`,自动 prepend `patches.addon/` 前缀(若行内无 `/`)。

## 3. Patch 打入方式

### 3.1 普通包:`.spec` 文件驱动(RPM 风格)

`src-openeuler/redis/redis.spec` 关键片段:

```spec
# 按声明顺序应用,序号即 spec 中出现顺序
Patch0000:    redis-conf.patch
# https://github.com/redis/redis/pull/3491 - man pages
Patch0001:    0001-1st-man-pageis-for-redis-cli-redis-benchmark-redis-c.patch
Patch0002:    0002-add-sw_64-support.patch

%prep
%setup -q -n %{name}-%{version} -b 6
mv ../%{name}-doc-%{doc_commit} doc
%autopatch -p1                # ★ 一行命令应用全部 Patch00XX
```

**机制**:
- `Patch00XX:` 声明 patch 源(可写相对仓库根的路径)
- `%autopatch -p1` 是 rpm-build 提供的宏:按 `Patch` 声明顺序遍历,逐条 `patch -p1`
- **没有**显式的 `%patch0` / `%patch1`(已弃用)
- patch 顺序由 `Patch00XX:` 行的**出现顺序**决定,不是行内序号本身

**无 `Upstream-Status:` 字段**。upstream 引用以**注释形式**贴在 `Patch00XX` 上方(`# https://github.com/...`),状态由 `%changelog` 隐式表达("Fix CVE-...-XX"、"add sw_64 support")。

### 3.2 内核包:`apply-patches` shell + `guards` Perl(SUSE-origin)

**`apply-patches`**(src-openeuler/kernel/apply-patches):

```sh
#!/bin/sh
# Given a series.conf file and a directory with patches, applies them to
# the current directory.  Used by kernel-source.spec.in and kernel-binary.spec.in
USAGE="$0 [--vanilla] <series.conf> <patchdir> [symbol ...]"

# 1. 解析 --vanilla + series.conf + patchdir + symbols
# 2. cp series.conf → tmp, append patches.addon/series (若存在)
# 3. "$DIR"/guards "$@" <"$series"  → 用 guards 过滤出本场景要打的 patch
# 4. sed 把每行包成 patch -s -F0 -E -p1 --no-backup-if-mismatch -i <patchdir>/<line>
# 5. set -ex + ERR trap 丢给 sh 执行
```

**`guards`**(src-openeuler/kernel/guards,**作者 Andreas Gruenbacher 2003-2007 Novell/SUSE**):

```perl
# +xxx   include if xxx is defined
# -xxx   exclude if xxx is defined
# +!xxx  include if xxx is not defined
# -!xxx  exclude if not defined
# 模式:
#   --check  校验 series 引用 vs 实际文件(报 "Not found" / "Unused")
#   --list   列出当前符号下要打的 patch
#   <default> 输出当前符号下要打的 patch 列表
```

**机制**:
- 内核**变体**(RT / haoc / raspberrypi / 主线)共享一个 `series.conf`
- 每个变体 build 时调用 `apply-patches series.conf . <variant-symbols...>`
- `guards` 根据 symbol 决定**该变体要打哪些 patch**
- 一个 patch 可在多个变体里,但只在变体符号匹配时打

**`patches.addon/series` 增量化**:openEuler 在主线 series.conf 之外,可叠加 `patches.addon/series` 做"开 Euler 变体专有 patch",`apply-patches` 自动 merge,实现"主线 + 衍生"分层。

### 3.3 两种方式对比

| 维度 | 普通包(%autopatch)| 内核包(apply-patches)|
|---|---|---|
| 驱动 | `.spec` 文件 | `series.conf` 文件 + symbol 参数 |
| 顺序权威 | `Patch00XX:` 行出现次序 | `series.conf` 行次序 |
| 条件包含 | 通过 `if 0%{?variant_x}` 包整段 patch | 行内 `+symbol` / `-symbol` 精细粒度 |
| 跨变体复用 | 多写几个 spec | 共享 series.conf + 传不同 symbol |
| Upstream-Status | 无显式字段,注释 + changelog 隐式 | 同样无显式字段 |
| 校验工具 | rpmbuild 自带 | `guards --check`(报 Not found / Unused)|

## 4. 生命周期(PR → review → build → release)

### 4.1 PR 创建

- 平台:gitcode.com(Gitee→AtomGit 已迁)+ 部分 GitHub mirror
- 一个 patch 一个 PR(可多个 commit,但**强烈建议 squash**)
- 分支模型:基于 `master` 开特性分支,merge 回 `master`

### 4.2 PR 提交后(Gate 阶段)

**触发者**:`sig-Gatekeeper/ci-bot`(gitee.com/openeuler/ci-bot → 已迁 atomgit.com/openeuler/ci-bot)
由 `robot-gitee-*` 系列 webhook 机器人实现:
- `robot-gitee-access` — 权限校验
- `robot-gitee-lifecycle` — PR 状态变更
- `robot-gitee-openeuler-review` — 评论 + 自动打标
- `robot-gitee-repo-watcher` — 仓库状态监听

### 4.3 CI Bot 评论时间线(标准 3 阶段)

| 阶段 | Bot 行为 | 触发 |
|---|---|---|
| 1. **门禁正在运行** | bot 立刻在 PR 评论 `门禁正在运行 #trigger/XXX` | PR 创建后 webhook 立即 |
| 2. **Code Check** | Jenkins `custom/<repo>` job 跑 checkpatch / checkformat / checkdepend / checkkabi / checkconflict / checkbinary | 几乎跟门禁并行 |
| 3. **License / SCA 检查** | `multiarch` AC job 跑 license + SCA | 在 clone 完成后 |
| 4. **多架构编译** | `multiarch` 触发 aarch64 / x86_64 / riscv64 并行 build | License 通过后 |
| 5. **结果通知** | bot 在 PR 评论 `check_package_license SUCCESS` + `check_build SUCCESS` / `FAILURE` | 全部架构完成 |

(具体阶段因仓库而异;kernel / iSulad / A-Tune / stratovirt / bishengjdk-8 等)

### 4.4 Maintainer Review

- 自动门禁通过后,等 maintainer review
- Maintainer 通过 `PR` 标签 + 评论 merge
- 自动 merge + auto-close source branch

### 4.5 Build → Release

- 合并后由 OBS(Open Build Service)或自建 Jenkins 拉源码 build
- Build 出 RPM → push 到 `repo.openeuler.org/<repo>/<arch>/Packages/`
- 镜像到 `packages.openeuler.org/`(包查询)

## 5. Dashboard / 观测

### 5.1 有/无的现状

| 平台 | 用途 | patch 维度信息 |
|---|---|---|
| `gitcode.com/src-openeuler/<pkg>` | 源码 PR review | 文件级 diff,无 patch 元数据聚合 |
| `repo.openeuler.org` | RPM 仓库(下载用) | 包元数据(RPM 头),无 patch 列表 |
| `packages.openeuler.org` | 包查询 dashboard | 显示**已发布 RPM 的 changelog 摘要**,但**不展示 patch 状态分布** |
| `openeuler.org/zh/monthly-summary` | 月度社区运作报告 | 文字总结,无 per-package patch dashboard |

**结论**:**openEuler 没有 per-package patch 状态 dashboard**。状态信息散在:
- PR 评论(GitCode 页面)
- `%changelog` 文本(RPM metadata)
- 维护者口口相传

### 5.2 间接观测点

- **CVE 修复追踪**:`https://www.openeuler.org/zh/security/cve/` 公开 CVE → 受影响包 + 修复版本的映射
- **PR 状态**:GitCode/AtomGit 原生 PR UI(per-patch 视角)
- **OBS Build 状态**:每个 PR 触发 multiarch build,bot 评论里能看到 7 架构成功/失败

## 6. 与本仓 v5.4 对比

| 维度 | openEuler | 本仓 v5.4 | 评价 |
|---|---|---|---|
| **模型定位** | 完整发行版(6000+ 包) | 单个上游 + patch overlay | 规模差 3-4 个数量级 |
| **包元数据** | `.spec`(Yocto recipe 同款) | `upstream.yaml`(Yocto recipe 同款) | 同款 |
| **patch 顺序权威** | 普通包:`Patch00XX:` 行次序;内核:`series.conf` 行次序 | `features.yaml` 内 `patches:` 列表 | openEuler 更分散(两套);本仓集中 |
| **patch 头部 schema** | 无强约束(只有 `# PR URL` 注释 + `%changelog`)| DEP-3 6 必填 + Yocto `Upstream-Status:` 8 状态枚举 | **本仓更严**,有 lint 强制 |
| **条件包含** | `guards` 行内 `+sym` / `-sym`(SUSE-origin) | `features.yaml` 中 `depends:` + `ACTIVE_FEATURES` 环境变量 | **本仓对齐 Kconfig depends**;openEuler 偏 Kconfig 早期风格 |
| **patch apply 工具** | rpm-build `%autopatch` + 自家 `apply-patches` shell | `apply_patch.sh`(Buildroot 风格 + inline python compose) | openEuler 双系统;本仓单点 |
| **跨变体复用** | 共享 `series.conf` + 传 symbol | `ACTIVE_FEATURES="f1 f2"` 选 feature 组合 | **思路同源**,openEuler 是 symbol-based,本仓是 name-based |
| **生命周期 dashboard** | 仅 PR UI + RPM changelog | 无(只 git log + PR review)| openEuler 也缺,**两个方案都没有 per-package patch dashboard** |
| **CI bot** | ci-bot + 5 个 robot 子系统(权限/标签/评论)| 3 步 GitHub Actions | openEuler 更复杂,但都是 CI 层职责 |
| **多架构 build** | 7 架构并行(aarch64/x86_64/riscv64/...)| 不涉及(本仓只管 patch overlay,build 是下游) | openEuler 负责全链;本仓只到 patch 为止 |
| **派生状态** | RPM changelog 累积(只追加不删)| 无派生状态(单值 `upstream_status`,真值在 patch 头) | **本仓更干净** |
| **跨包复用** | 6,000+ 包,跨包关系靠 RPM `BuildRequires` | 单仓内 N 个 feature,跨 feature 关系靠 `depends` | 规模差异 |

## 7. 借鉴点(可学的)

| 借鉴点 | 落地难度 | 理由 |
|---|---|---|
| **`%changelog` 累积式变更记录** | 低 | RPM 生态惯例,审计友好;本仓目前没有 per-patch changelog。可在 `tools/` 加 `changelog.py <features.yaml>` 走 git log + patch 头生成 |
| **跨变体复用** `series.conf + symbol` | 中 | 与 Kconfig `depends` / `default` 思路同源。本仓 v5.0 已用 `ACTIVE_FEATURES`,等同 openEuler 传 symbol |
| **`patches.addon/series` 分层** | 中 | "主线 + 衍生" 二层系列文件,本仓可考虑为 `features.yaml` 配一个 `features.addon.yaml`,自动 prepend |
| **注释式 upstream 引用** `# https://github.com/redis/redis/pull/3491` | 低 | openEuler 用注释,本仓用 `Upstream-PR:` 字段(更机器友好)。两个思路都对,可保留本仓做法 |
| **架构特定 KABI 白名单** | 不适用 | 仅内核相关,本仓非内核 |
| **多架构 CI 并行** | 不适用 | 本仓不 build,只提供 patch |

## 8. 不借鉴点(说明理由)

| openEuler 做法 | 不借鉴理由 |
|---|---|
| **没有 `Upstream-Status:` 字段** | 状态信息散在 changelog + 注释,机器不可读。本仓 `Upstream-Status: <8 状态枚举>` 更可追溯 |
| **`Patch00XX` 4 位序号** | 本仓 `0001-` 已用,等价。但 `Patch0000: <file>` 重复声明文件名(序号 + 行序)实属冗余,本仓 `patches:` 列表单维 |
| **双机制并存**(`%autopatch` + `apply-patches`)| 双系统增加认知负担。本仓单点 `apply_patch.sh` 即可 |
| **缺 per-package patch dashboard** | openEuler 也没解决,不是本调研能借鉴的方向 |
| **`.spec` 顺序号 + changelog 注释** | `.spec` 是 RPM 生态特有的,本仓对齐 Yocto recipe 字段更通用 |
| **guards 行内条件语法 `+sym` / `-sym`** | Perl 时代风格,可读性一般;本仓用 `depends:` 显式声明 + Kconfig 风格更现代 |

## 9. 关键 takeaway

1. **openEuler 与本仓的 patch 管理思路同源**(都是"声明式 + 显式顺序 + 条件包含"),只是规模/工具/平台不同
2. **openEuler 没有 per-package patch dashboard** — 这是一个**行业空白**,本仓暂时也不用做
3. **openEuler 也没有强 schema 约束** patch header — 本仓的 DEP-3 + Yocto 8 状态校验**比 openEuler 更严**
4. **双机制并存是 openEuler 的历史包袱**(普通包 RPM 风格 + 内核包 SUSE 风格),本仓 v5.0 起就**单点统一**,这是本仓相对 openEuler 的**一个优势**
5. **`%changelog` 累积** 是 openEuler 一个值得学的审计型特性,本仓目前缺

## 10. 参考资料

- [src-openeuler/redis 仓库](https://gitcode.com/src-openeuler/redis)
- [src-openeuler/kernel 仓库](https://gitcode.com/src-openeuler/kernel)
- [src-openeuler/kernel apply-patches 脚本](https://gitcode.com/src-openeuler/kernel/blob/openEuler-24.03-LTS/apply-patches)
- [src-openeuler/kernel guards 脚本](https://gitcode.com/src-openeuler/kernel/blob/openEuler-24.03-LTS/guards)(作者 Andreas Gruenbacher, Novell/SUSE 2003-2007)
- [openEuler ci-bot](https://gitee.com/openeuler/ci-bot)(已迁 atomgit)
- [openEuler 包查询](https://packages.openeuler.org)
- [openEuler 月度社区报告](https://www.openeuler.org/zh/monthly-summary/)
- [openEuler Maintainer Doc — Lifecycle](https://docs.openeuler.org/en/developers/process/maintainer-lifecycle.html)
- [openEuler Wiki — PR Process](https://openeuler.org/wiki/Repository_management/Pull-Requests)
- [openEuler 博客 — RPM Spec 文件解读](https://www.openeuler.org/en/blog/2022/07/26/RPM-Package-Spec-File.html)
- [openEuler 博客 — Upstream/Backport/CVE 深度分析](https://openeuler.org/en/blog/2022/09/15/Upstream-Backport-and-CVE-Patches-in-openEuler-A-deep-analysis.html)
- [kpatch (openEuler 社区,运行时补丁)](https://gitee.com/openeuler-community/kpatch/blob/master/README.md)

## 11. 本调研对本仓的可能后续行动

按 ROI 排序:

1. **加 `tools/changelog.py <features.yaml>`**:走 git log + patch 头生成 per-feature changelog(借鉴 openEuler `%changelog` 累积思路)
2. **加 `features.addon.yaml` 支持**:为 `apply_patch.sh` 加 "主线 + 衍生" 二层 compose(借鉴 openEuler `patches.addon/series`)
3. **不引入** Per-package patch dashboard(行业空白,本场景 ROI 低)
4. **不引入** KABI 白名单(非内核)
5. **不引入** ci-bot 5 子系统(过度工程,GitHub Actions 3 步已够)