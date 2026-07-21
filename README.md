# Redis 网络优化特性

> 当前设计版本:`features.yaml + depends DFS + upstream_status 单值`,schema 见 [docs/schemas.md](./docs/schemas.md)
> 完整变更历史走 `git log --oneline`

## 项目品牌名称

Kunpeng BoostKit Redis

## 项目介绍

Kunpeng BoostKit Redis 是基于上游 Redis 的 patch overlay,在固定上游版本基线上叠加
BoostKit 团队维护的 ARM/Kunpeng 平台优化 patch。

**核心模型**:version-centric + feature 声明(**集合 5 家业界方案之长**):
- **Yocto/OpenEmbedded** recipe 字段 + `Upstream-Status` 8 状态语义
- **DEP-3** patch 头 schema(6 必填)
- **Buildroot** `apply-patches.sh` 单点 series 应用器
- **OpenWrt** `package/<name>/Config.in` + `Makefile` 特性声明 + 条件 `PATCHFILES`(本仓 v5.0 主线)
- **Linux kernel** `Kconfig` `depends` / `select` / `default` 语义

**v5.0 关键升级**:用 `patches/features.yaml`(OpenWrt Config.in 风格)替代 v4.0
的 `series.<profile>`,客户用 `ACTIVE_FEATURES` 选特性组合;compose 逻辑
**集成到 `apply_patch.sh` 内部**(用户约束:不另起新脚本)。

见 [docs/governance.md §2](./docs/governance.md#2-业界出处集合-5-家)。

## 目录结构

```text
boostkit-patches-governance-demo/
├── README.md / README_en.md            # 本文件
├── LICENSE.txt                          # 上游 license 全文
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── lint_patch_headers.py            # DEP-3 6 必填字段校验
│   ├── lint_series.py                   # v5.0 起 lint features.yaml(schema + depends + DEP-3 必填)
│   └── workflows/
│       ├── ci.yml                       # 3 步:verify + patch 头 lint + features lint
│       └── build-perf.yml               # 骨架演示 workflow(matrix + clean apply 真跑 + 后续 echo)
├── tools/
│   ├── verify.sh                        # 仓根禁放 + upstream.yaml schema(委托 apply_patch.sh --features)
│   └── apply_patch.sh                   # ★ Buildroot 风格 series 应用器 + v5.0 --features 模式(inline compose)
├── docs/
│   ├── governance.md                    # ★ 设计原理 + 5 家业界出处
│   ├── schemas.md                       # ★ 三类 YAML/header 字段权威定义
│   ├── version-yaml-spec.md             # 详细字段说明(以 schemas.md 为准)
│   └── (产品指南 zh/en 保留)
└── versions/
    └── <upstream-id>/                   # 例如 redis-7.0.15
        ├── upstream.yaml                # Yocto recipe 字段 + upstream pin + 治理归属
        └── patches/
            ├── features.yaml            # ★ feature 声明(OpenWrt Config.in 风格,单一权威)
            └── features/<feature>/      # 一特性一目录
                └── *.patch              # DEP-3 邮件式头(6 必填)+ diff
```

## 快速开始

### 1. 上游基线 + patch 顺序一目了然

`versions/redis-7.0.15/upstream.yaml`(Yocto recipe 段 + upstream pin):

```yaml
SUMMARY: "Redis in-memory data structure store with Kunpeng ARM optimizations"
DESCRIPTION: |
  Redis is an open source, in-memory data structure store used as a database,
  cache, message broker, and streaming engine. BoostKit overlay.
HOMEPAGE: "https://redis.io"
LICENSE: "BSD-3-Clause"
LIC_FILES_CHKSUM: "file://COPYING;md5=508cbf69e54be9b31b53b42e7411f8c4"
SECTION: "network/database"

upstream:
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: f35f36a265403c07b119830aa4bb3b7d71653ec9

meta:
  owner: twwang@boostkit
  maintainer: twwang@boostkit
  last_review: 2026-07-20
  lifecycle: active
```

`versions/redis-7.0.15/patches/features.yaml`(OpenWrt Config.in 风格,单一权威):

```yaml
# 业界参照:OpenWrt package/<name>/Config.in + Kconfig depends + Yocto 条件 SRC_URI
features:
  kunpeng-hw-accel:
    title: "Kunpeng ARM 硬件加速(io_uring 适配 + DTOE DMA 网络路径)"
    patches:
      - 0001-hw-kunpeng-adapt-iouring.patch
      - 0002-perf-kunpeng-adapt-dtoe.patch
    depends: []
    default: true                                # 默认激活
    # feature 主导上游状态(Yocto 8 状态枚举单值)
    upstream_status: Inappropriate
  jemalloc-arm64:
    title: "jemalloc ARM64 pointer-tag + GC decay 策略优化"
    patches:
      - 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
    depends: []
    default: false                               # 默认不激活
    upstream_status: Submitted
  rdb-aof-fallback:
    title: "RDB 损坏时降级到 AOF,避免硬停服"
    patches:
      - 0001-perf-rdb-fallback-aof.patch
    depends: []
    default: true
    upstream_status: Submitted
```

物理 patch 按 feature 分目录:

```text
versions/redis-7.0.15/patches/features/
├── kunpeng-hw-accel/
│   ├── 0001-hw-kunpeng-adapt-iouring.patch
│   └── 0002-perf-kunpeng-adapt-dtoe.patch
├── jemalloc-arm64/
│   └── 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
└── rdb-aof-fallback/
    └── 0001-perf-rdb-fallback-aof.patch
```

### 2. 本地验证

```bash
# 1. 仓根干净 + upstream.yaml schema + clean clone + 按 features.yaml apply
#    (内部委托给 tools/apply_patch.sh --features,Buildroot 风格 + v5.0 inline compose)
bash tools/verify.sh

# 2. DEP-3 patch 头 schema 校验(6 必填:Description/Origin/Upstream-Status/Applies-To/Maintainer/Last-Update)
python3 .github/lint_patch_headers.py versions/*/patches/

# 3. features.yaml schema + depends 解析 + DEP-3 必填字段
python3 .github/lint_series.py versions/*/patches/
```

### 2.5 Feature 组合(同一 upstream 多特性组合)

需要只 apply 部分 feature 时(例:客户只要 rdb-aof-fallback 可靠性),用 `ACTIVE_FEATURES`:

```bash
# 默认组合 = features.yaml 中 default:true 的并集(本仓 = kunpeng-hw-accel + rdb-aof-fallback)
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build

# 客户 A:只要 rdb-aof-fallback 可靠性
ACTIVE_FEATURES="rdb-aof-fallback" bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build-a

# 客户 B:全开(包括默认不激活的 jemalloc-arm64)
ACTIVE_FEATURES="kunpeng-hw-accel jemalloc-arm64 rdb-aof-fallback" bash tools/apply_patch.sh ... --features ... /tmp/build-b

# 等价的 --active 参数(便于 CI / 测试传参)
bash tools/apply_patch.sh ... --features ... --active "jemalloc-arm64 rdb-aof-fallback" /tmp/build-c
```

`depends` 字段让 feature 自动 include 依赖项(例:rdb-aof-fallback.depends=[kunpeng-hw-accel] 时,
激活 C 会自动先 apply A)。

`depends` 字段双业界出处:
- **Linux kernel Kconfig** `depends on`(同款 DFS 深度优先解析 + 环依赖 hard-fail)
- **OpenWrt** `package/<name>/Makefile` 条件 `PATCHFILES`(依赖激活后才进 build)
详见 [docs/governance.md §2.5](./docs/governance.md#25-linux-kernel-kconfig--depends--select--default-语义)
+ [docs/version-yaml-spec.md §3](./docs/version-yaml-spec.md#3-patchesfeaturesyamlopenwrt-configin-风格--v50-单一权威)。

### 2.6 单独跑 feature apply(Buildroot 风格)

```bash
# 默认组合
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build
```

### 3. 在 Kunpeng 上构建

```bash
# 1) clean clone + apply default features(走 tools/apply_patch.sh --features,Buildroot 风格单点实现)
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build

# 2) build(需 BoostKit 内核自带 KRAIO SDK RPM)
cd /tmp/build/upstream
make distclean && make -j$(nproc) -DHAVE_KRAIO
```

## 兼容性

| 维度 | 支持范围 |
|---|---|
| OS | openEuler 22.03 LTS SP4 / 24.03 LTS |
| Redis | 6.0.20 / 7.0.15(见 `versions/`) |
| 架构 | aarch64(Kunpeng) |
| 内核 | 内核自带 KRAIO SDK RPM 包 |

## 出处与规范

- **设计原理 + 业界对齐**:[docs/governance.md](./docs/governance.md)
- **字段权威定义**:[docs/schemas.md](./docs/schemas.md)
- **详细字段说明**:[docs/version-yaml-spec.md](./docs/version-yaml-spec.md)(以 schemas.md 为准)
- **工具脚本 → 业界出处对照表**:[docs/governance.md §2.7](./docs/governance.md#27-tools-工具脚本--业界出处对照表)
- **操作步骤(新增/废弃 patch 等)**:[docs/governance.md §4](./docs/governance.md#4-常见操作)

业界出处(5 家,v5.1 起纯 5 家已简并):
- **Yocto/OpenEmbedded** — recipe 字段(SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION)+ `Upstream-Status` 8 状态
- **DEP-3** (Debian) — patch 头 schema + 6 必填字段
- **Buildroot** `apply-patches.sh` — series 应用器单点实现
- **OpenWrt** `package/<name>/Config.in` + `Makefile` — 特性声明 + 条件 `PATCHFILES`(本仓 v5.0 主线)
- **Linux kernel** `Kconfig` — `depends` / `select` / `default` 语义(深度优先解析 + 环依赖检测)

**v5.0 关键升级**:用 `patches/features.yaml`(OpenWrt Config.in 风格)替代 v4.0
的 `series.<profile>`,客户用 `ACTIVE_FEATURES` 选特性组合;compose 逻辑
**集成到 `apply_patch.sh` 内部**(用户约束:不另起新脚本)。

**v5.1 简化**:删除 `tools/gen_inventory.py` + `inventory.json` 派生体系
(gitignored 派生 + CI 同义反复,价值有限)。本地 3 工具全绿即可。

## 贡献

只接受 PR,不接受直推 master。流程:

1. 新增 patch → 放 `patches/features/<feature>/` + 写 DEP-3 头(6 必填)+ 在 `features.yaml` 加 entry
2. 跑本地 3 工具全绿(verify + 2 个 lint)
3. 开 PR,触发 `ci.yml` 3 步 + `build-perf.yml` matrix(骨架)
4. 维护者 review → merge

## 许可证

- 本仓 patch overlay:Apache 2.0(见 [LICENSE.txt](./LICENSE.txt))
- 上游 Redis:BSD-3-Clause(各 patch 头部保留原始 license)
- 产品文档:CC-BY 4.0(见 [docs/LICENSE](./docs/LICENSE))

