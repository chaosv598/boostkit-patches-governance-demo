# Patch Overlay 治理设计

## 1. 模型概述

本仓治理"在固定上游基线上叠加 N 个 patch"的问题,采用业界最广泛采用的
**version-centric + 显式 `patches/series`** 模型。**v3.0 集合 Yocto / DEP-3 /
Buildroot-OpenWrt 三家之长**:

```
<upstream-id>/
├── upstream.yaml              # Yocto recipe 字段 + 上游基线 + 治理归属
└── patches/
    ├── series                 # ★ 唯一权威顺序(自上而下应用)
    └── *.patch                # DEP-3 邮件式头(6 必填)+ diff
```

**配套工具**(仓根):
- `tools/apply_patch.sh` — Buildroot 风格 series 应用器(单点实现)
- `tools/verify.sh` — 一键验证(仓根禁放 + upstream.yaml schema + 委托 apply_patch.sh)

**核心原则**:

- **唯一权威顺序** = `patches/series`,改顺序只动 1 行
- **filename `0001-` 仅辅助阅读** — 可重命名,不影响顺序
- **patch 元数据物理上紧贴 patch** — DEP-3 邮件式头(6 必填:Description /
  Origin / Upstream-Status / Applies-To / Maintainer / Last-Update)
- **`upstream.yaml` recipe 段对齐 Yocto** — SUMMARY/LICENSE/HOMEPAGE/
  LIC_FILES_CHKSUM/SECTION,license audit / 包归属可直接复用
- **apply 单点实现** — `apply_patch.sh` Buildroot 同款,verify.sh / build-perf
  / 本地复跑都走它,绝不重复实现
- **不引入 DAG** — 默认线性足够,业界共识

完整字段定义见 [version-yaml-spec.md](./version-yaml-spec.md)。

---

## 2. 业界出处(集合 5 家)

本设计综合以下 5 个成熟方案的最大公约数。

### 2.1 Yocto/OpenEmbedded — `upstream.yaml` recipe 字段 + `Upstream-Status`

**出处**:
- Recipe 字段: https://docs.yoctoproject.org/ref-manual/variables.html
- Upstream-Status: https://docs.yoctoproject.org/dev/contributor-guide/recipe-style-guide.html

Yocto recipe 用顶层变量描述包元数据,patch 用 `Upstream-Status:` 描述合入状态:

```text
SUMMARY = "Redis in-memory data structure store"
HOMEPAGE = "https://redis.io"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://COPYING;md5=508cbf..."

# Per-patch (in patch header):
Upstream-Status: Submitted
Upstream-Status: Backport [upstream commit URL]
Upstream-Status: Inappropriate [oe specific]
```

**对齐点**:
- `upstream.yaml` 段 1(SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION)
  字段名 = Yocto 同款,可被 license audit / 发布单直接读取
- `Upstream-Status` **8 个枚举值直接对齐 Yocto 命名**:`Pending / Submitted
  / Accepted / Rejected / Backport / Inappropriate / Denied / Inactive-Upstream`
  (仅把 Yocto 的 `[mailing-list-or-URL]` 拆为单独的 `Upstream-PR:` 字段,更结构化)

### 2.2 DEP-3 (Debian Enhancement Proposal 3) — patch 头 schema

**出处**: https://dep-team.pages.debian.net/deps/dep3/

DEP-3 是 Debian 官方 patch header 格式规范,定义必填字段语义:

```text
From: Author <author@example.com>
Subject: Short single-line title
Description: Long multi-line description of what and why
Origin: URL or vendor/branch name (where the patch came from)
Last-Update: YYYY-MM-DD
Bug-Debian: http://bugs.debian.org/123456
Forwarded: yes/no/URL
Applied-Upstream: <commit> / <version> / <URL>
```

**对齐点**:本仓 patch 头采用 DEP-3 6 必填字段:
- `Description` / `Origin` / `Last-Update` —— DEP-3 标准
- `Upstream-Status` —— Yocto(同 §2.1)
- `Applies-To` / `Maintainer` —— DEP-3 扩展(自定义但语义清晰)

### 2.3 Buildroot `support/scripts/apply-patches.sh` — series 应用器

**出处**: https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh

Buildroot 用单点 `apply-patches.sh` 脚本消费 `series` 文件,所有 package 共享:

```bash
# Buildroot apply-patches.sh 节选
while read patch; do
    case "$patch" in ""|\#*) continue ;; esac
    patch=$(echo "$patch" | xargs)
    if ! patch -p1 -d "$target_dir" -i "$patch_dir/$patch"; then
        echo "Failed to apply $patch"; exit 1
    fi
done < "$series"
```

**对齐点**:本仓 `tools/apply_patch.sh` Buildroot 同款:
- 行格式一致(空行 / `#` 注释跳过)
- 行内 guards(`-p1` `-R`)透传
- 失败行为可配置(默认 warning,可改 hard)

**改进 vs Buildroot**:用 `git apply`(集成 git)而非 raw `patch`,自带 fetch cache。

### 2.4 OpenWrt `patches/series` + `patch-kernel.sh` — 同款

**出处**: https://github.com/openWRT/openwrt/tree/main/scripts

OpenWrt 每个 package 一个 `patches/series`,由 `scripts/patch-kernel.sh` 统一应用。

**对齐点**:本仓 `patches/series` 格式(每行 1 条 patch 路径)与 OpenWrt 完全一致。
本仓不写 `patch-kernel.sh`,而用更轻量的 `apply_patch.sh`(只 apply,不打包)。

### 2.5 Quilt / Debian `debian/patches/series` + SUSE kernel-source

**出处**:
- Quilt: https://salsa.debian.org/kernel-team/linux/-/tree/master/debian/patches
- SUSE: https://github.com/openSUSE/kernel-source/blob/master/series.conf

Debian kernel 团队维护上千个 patch,用 `series` 自上而下应用。
SUSE kernel-source 用 `series.conf` 额外带 `Git-commit:` 校验和 + guards。

**对齐点**:本仓 `patches/series` = Quilt 同款。

**未对齐点**(刻意):
- **不引入 `.pc/` 暂存** —— Quilt 的 push/pop 栈对 5–50 patch 量级过度设计
- **不引入 SHA-256 校验和** —— SUSE 的硬校验对小仓 overkill,commit 链本身是审计凭据
- **不引入 guards 机制** —— v3.0 暂不需要,未来按 SUSE `series.conf` 演进

---

## 3. 工作流

### 3.1 `ci.yml`(PR / push master 时触发)

3 步顺序:

| 步骤 | 工具 | 职责 |
|---|---|---|
| 1 | `bash tools/verify.sh` | 仓根禁放 + upstream.yaml schema(Yocto 字段警告)+ 委托 `apply_patch.sh` |
| 2 | `python3 .github/lint_patch_headers.py` | DEP-3 6 必填 + 额外 3 必填 + 条件必填 |
| 3 | `python3 .github/lint_series.py` | series 一致性(无孤儿 + 无重复 + 所有 entry 存在) |

### 3.2 `build-perf.yml`(PR / push master / workflow_dispatch 触发,骨架演示)

> **本仓 CI 上的 build-perf 是骨架演示 workflow**(demonstration skeleton),
> 不实际跑编译/bench。原因:编译依赖 BoostKit 内核侧 **KRAIO SDK**
> (`networking.c` 引用 `<kraio.h>`,只有装好 BoostKit 内核 RPM 的真
> Kunpeng 机器才有该头文件),普通 `ubuntu-22.04` GHA runner 必然
> `fatal error: kraio.h: No such file or directory`。

**触发方式**:
- `pull_request` 到 `master` — 骨架演示走完,Step Summary 列出每个 step 的"实际 / 演示"
- `push` 到 `master` — 同上(合并后 smoke)
- `workflow_dispatch` — 真 Kunpeng runner 手动触发完整流程

**矩阵生成**:从 `versions/*/upstream.yaml` 动态展开(不写死 redis-7.0.15)。

**骨架里实际跑的**:
- matrix 检测(读 `versions/*/upstream.yaml`)
- 调用 `tools/apply_patch.sh` clean clone + 按 `patches/series` `git apply`
  — 与 `verify.sh` 二次确认等价(真信号)

**骨架里只 echo 不真跑的**:
- apt-get 安装 build deps + memtier 源码编译
- make patched redis
- memtier_benchmark

**真 Kunpeng runner 部署**:把每个 `[skeleton]` step 的 `run: echo ...` 替换成
`run: <实际命令>` 即可(完整命令见下"本地复跑")。整个 workflow 结构(metrics /
matrix / cache / artifact upload)已就位,直接填血肉。

**本地复跑**(给开发者,真 Kunpeng 机器上):

```bash
# 1. clean clone upstream + apply series(走 tools/apply_patch.sh,Buildroot 风格)
bash tools/apply_patch.sh \
  https://github.com/redis/redis \
  f35f36a265403c07b119830aa4bb3b7d71653ec9 \
  versions/redis-7.0.15/patches/series \
  versions/redis-7.0.15/patches \
  /tmp/build

# 2. 编译 + 性能基准
cd /tmp/build/upstream
make distclean
make -j$(nproc) USE_KRAIO=0
src/redis-server --port 6399 --daemonize yes --dbfilename dump.rdb \
                  --save '' --appendonly no --maxmemory 256mb \
                  --logfile /tmp/redis.log
src/redis-benchmark -p 6399 -c 200 -d 3 -n 10000000 -r 10000000 \
                     -t set,get --threads 20 -q
```

---

## 4. 常见操作

### 4.1 新增 patch

```bash
# 1. 在 versions/<upstream-id>/patches/ 加 .patch 文件
cp my-new.patch versions/redis-7.0.15/patches/0005-my-new.patch

# 2. 编辑 DEP-3 邮件式头,必填 6 字段:
#    Description (≥20 字符)/ Origin / Upstream-Status / Applies-To / Maintainer / Last-Update
#    + 额外 3 必填:From / Subject / Signed-off-by
#    + 条件必填(按 Upstream-Status)

# 3. 在 versions/redis-7.0.15/patches/series 末尾追加一行
echo "0005-my-new.patch" >> versions/redis-7.0.15/patches/series

# 4. 本地 3 工具全 rc=0
bash tools/verify.sh
python3 .github/lint_patch_headers.py versions/*/patches/
python3 .github/lint_series.py versions/*/patches/

# 5. 开 PR,触发 ci.yml + build-perf.yml
```

### 4.2 改 patch 状态(如 Submitted → Accepted)

直接编辑 patch 头:
```diff
- Upstream-Status: Submitted
- Upstream-PR: https://github.com/redis/redis/pull/12345
+ Upstream-Status: Accepted
+ Upstream-PR: https://github.com/redis/redis/pull/12345
+ Upstream-Commit: deadbeef1234567890abcdef1234567890abcdef
```

### 4.3 改上游版本(如 7.0.15 → 7.0.16)

```bash
# 1. 改 versions/redis-7.0.15/upstream.yaml:
sed -i 's/version: 7.0.15/version: 7.0.16/; s|commit: f35f36a.*|commit: <new-sha>|' \
    versions/redis-7.0.15/upstream.yaml

# 2. 重新跑 apply_patch.sh 看 patch 是否仍能 apply
bash tools/apply_patch.sh \
  https://github.com/redis/redis \
  <new-sha> \
  versions/redis-7.0.15/patches/series \
  versions/redis-7.0.15/patches \
  /tmp/build

# 3. 不能 apply 的 patch 进入 "rebase needed" 流程(参考 4.4)
```

### 4.4 废弃 patch

```bash
# 在 series 删除该 patch 路径(保留 .patch 文件以便历史追溯)
sed -i '/0002-perf-kunpeng-adapt-dtoe.patch/d' \
    versions/redis-7.0.15/patches/series

# 或在 patch 头改 Upstream-Status: Inappropriate + Whitelist-Reason
# 让 apply_patch.sh 仍然 apply 但标记废弃
```

---

## 5. FAQ

### Q1: 为什么不用 Quilt?

Quilt 适合 Debian kernel 那种 1000+ patch 的场景,`.pc/` 暂存 + push/pop 栈
能力很强。本仓 5–50 patch 量级,`apply_patch.sh` + `git apply` 足够,引入 Quilt
会带不必要的复杂度。

### Q2: 为什么不用 SUSE `series.conf` SHA-256?

SUSE 面向 Build Service / RPM 自动化,patch 可能在多个镜像 / 时间点分发,硬校验
是必要的。本仓是 GitHub 单一 source of truth,commit hash 本身是 audit trail,
不需要额外 SHA 校验和。如果将来要做 reproducibility build,可演进到 SUSE 模式。

### Q3: upstream.yaml 的 Yocto 字段不填会报错吗?

不会,只 warning(`verify.sh` 提示 `⚠ SUMMARY missing`)。强推荐填 — license
audit / 包归属需要。但不阻塞 CI。

### Q4: DEP-3 6 必填字段是硬要求吗?

是。`lint_patch_headers.py` rc=1 = block merge。Description 太短(<20 字符)
或 Last-Update 格式错也会 fail。

### Q5: apply_patch.sh 的 fetch cache 怎么复用?

cache 放在 `<work_dir>/upstream/`,二次跑不会重新 clone。如果想完全清空,删
`/tmp/<vid>/upstream/` 目录即可。

### Q6: 真 Kunpeng runner 上的 build-perf 怎么启用?

把 `build-perf.yml` 里每个 `[skeleton]` step 的 `run: | echo ...` 替换成
`run: <实际命令>`(apt-get / make / memtier),workflow 其它结构不动。
然后在 repo Settings → Runners 上加 self-hosted runner label,workflow 用
`runs-on: [self-hosted, kunpeng]` 替换 ubuntu-latest。
