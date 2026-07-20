# Redis 网络优化特性

## 项目品牌名称

Kunpeng BoostKit Redis

## 项目介绍

Kunpeng BoostKit Redis 是基于上游 Redis 的 patch overlay,在固定上游版本基线上叠加
BoostKit 团队维护的 ARM/Kunpeng 平台优化 patch。

**核心模型**:version-centric + 显式 `patches/series`(**集合 5 家业界方案之长 + 2 项扩展**):
- **Yocto/OpenEmbedded** recipe 字段 + `Upstream-Status` 8 状态语义
- **DEP-3** patch 头 schema(6 必填)
- **Buildroot** `apply-patches.sh` 单点 series 应用器
- **OpenWrt** `patches/series` 行格式
- **Quilt/Debian** `debian/patches/series` 顺序语义
- **本仓扩展**:`series.<profile>` profile 系列文件(同款于 Buildroot variant)
- **本仓扩展**:`tools/gen_inventory.py` 派生 `inventory.json`(Buildroot/OpenWrt 风格)

见 [docs/governance.md §2](./docs/governance.md#2-业界出处集合-5-家-本仓-2-扩展)。

## 目录结构

```text
boostkit-patches-governance-demo/
├── README.md / README_en.md            # 本文件
├── LICENSE.txt                          # 上游 license 全文
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── lint_patch_headers.py            # DEP-3 6 必填字段校验
│   ├── lint_series.py                   # series + series.* profile 一致性校验
│   └── workflows/
│       ├── ci.yml                       # 4 步:verify + patch 头 lint + series lint + inventory check
│       └── build-perf.yml               # 骨架演示 workflow(matrix + clean apply 真跑 + 后续 echo)
├── tools/
│   ├── verify.sh                        # 仓根禁放 + upstream.yaml schema(委托 apply_patch.sh)+ 派生 inventory
│   ├── apply_patch.sh                   # ★ Buildroot 风格 series 应用器(单点实现)
│   └── gen_inventory.py                 # 派生 inventory.json(Buildroot/OpenWrt 风格)
├── docs/
│   ├── governance.md                    # ★ 设计原理 + 5 家业界出处 + 2 项本仓扩展
│   ├── version-yaml-spec.md             # ★ 字段权威定义
│   └── (产品指南 zh/en 保留)
└── versions/
    └── <upstream-id>/                   # 例如 redis-7.0.15
        ├── upstream.yaml                # Yocto recipe 字段 + upstream pin + 治理归属
        └── patches/
            ├── series                   # ★ 唯一权威顺序(默认 profile)
            ├── series.<profile>         # profile 系列文件(可选,如 series.minimal / series.security)
            ├── inventory.json           # 派生(不入仓,gitignore)
            └── *.patch                  # DEP-3 邮件式头(6 必填)+ diff
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

`versions/redis-7.0.15/patches/series`(自上而下应用):

```text
0001-hw-kunpeng-adapt-iouring.patch
0002-perf-kunpeng-adapt-dtoe.patch
0003-perf-jemalloc-arm64-pointer-tag-and-gc.patch
0004-perf-rdb-fallback-aof.patch
```

### 2. 本地验证

```bash
# 1. 仓根干净 + upstream.yaml schema + clean clone + 按 series apply + 派生 inventory
#    (内部委托给 tools/apply_patch.sh,Buildroot 风格)
bash tools/verify.sh

# 2. DEP-3 patch 头 schema 校验(6 必填:Description/Origin/Upstream-Status/Applies-To/Maintainer/Last-Update)
python3 .github/lint_patch_headers.py versions/*/patches/

# 3. series 一致性(无孤儿 + 无重复;profile 文件 series.* 自动识别)
python3 .github/lint_series.py versions/*/patches/

# 4. inventory.json 与 patch 头 + series 一致(忽略 generated_at 时间戳)
python3 tools/gen_inventory.py --check versions/*/
```

### 2.6 Profile 系列文件(同一 upstream 多 patch 集合)

需要只 apply 部分 patch 时(例:CI 跳过 HW-specific 优化),用 `series.<profile>`:

```bash
# 创建 profile 系列文件(普通 series 格式,每行 1 patch)
cat > versions/redis-7.0.15/patches/series.ci <<'EOF'
# CI smoke profile:只跑 0001 + 0004,跳过 0002 (Kunpeng HW) / 0003 (jemalloc 子模块)
0001-hw-kunpeng-adapt-iouring.patch
0004-perf-rdb-fallback-aof.patch
EOF

# profile 直接复用 apply_patch.sh(接受任意 series 文件)
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    versions/redis-7.0.15/patches/series.ci \
    versions/redis-7.0.15/patches \
    /tmp/build-ci

# inventory.json 自动反映新 profile(派生物,不入仓)
python3 -c "import json; d=json.load(open('versions/redis-7.0.15/patches/inventory.json')); \
    [print(f\"{p['file']:50s} profiles={p['in_profiles']}\") for p in d['patches']]"
```

业界出处:Buildroot `package/<name>/<name>-<variant>.patch` / OpenWrt `PATCHFILES` + `CONFIG_*`。
详见 [docs/version-yaml-spec.md §3.3](./docs/version-yaml-spec.md#33-profile-系列文件seriesprofile--本仓扩展)。

### 2.5 单独跑 series apply(Buildroot 风格)

```bash
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    versions/redis-7.0.15/patches/series \
    versions/redis-7.0.15/patches \
    /tmp/build
```

### 3. 在 Kunpeng 上构建

```bash
# 1) clean clone + apply series(走 tools/apply_patch.sh,Buildroot 风格单点实现)
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    versions/redis-7.0.15/patches/series \
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
- **字段权威定义**:[docs/version-yaml-spec.md](./docs/version-yaml-spec.md)
- **操作步骤(新增/废弃 patch 等)**:[docs/governance.md §4](./docs/governance.md#4-常见操作)

业界出处(5 家 + 2 项本仓扩展):
- **Yocto/OpenEmbedded** — recipe 字段(SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION)+ `Upstream-Status` 8 状态
- **DEP-3** (Debian) — patch 头 schema + 6 必填字段
- **Buildroot** `apply-patches.sh` — series 应用器单点实现
- **OpenWrt** `patches/series` — 行格式
- **Quilt/Debian** `debian/patches/series` — 顺序语义
- **本仓扩展** — `series.<profile>` profile 系列文件(Buildroot variant 同款)
- **本仓扩展** — `tools/gen_inventory.py` 派生 inventory.json(Buildroot `pkg-stats` / OpenWrt `metadata.pl` 同款)

## 贡献

只接受 PR,不接受直推 master。流程:

1. 新增 patch → 写 DEP-3 头(6 必填)+ 修改 `patches/series` 一行
2. 跑本地 4 工具全绿(verify 含 inventory 派生 + 3 lint 工具)
3. 开 PR,触发 `ci.yml` 4 步 + `build-perf.yml` matrix(骨架)
4. 维护者 review → merge

## 许可证

- 本仓 patch overlay:Apache 2.0(见 [LICENSE.txt](./LICENSE.txt))
- 上游 Redis:BSD-3-Clause(各 patch 头部保留原始 license)
- 产品文档:CC-BY 4.0(见 [docs/LICENSE](./docs/LICENSE))

## 变更通知

- **2026-07-20** v4.0:新增 `tools/gen_inventory.py`(Buildroot/OpenWrt 风格派生
  inventory.json)+ `series.<profile>` profile 系列文件。inventory.json 入
  `.gitignore`,由 `tools/verify.sh` 自动重生成;CI 加第 4 步
  (`gen_inventory.py --check`)。`lint_series.py` 自动识别 `series.<profile>`。
- **2026-07-20** v3.0:集合 Yocto recipe 字段 + DEP-3 patch 头 + Buildroot
  `apply-patches.sh`。新增 `tools/apply_patch.sh`(单点 series 应用器),
  `upstream.yaml` 加 Yocto 字段(SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/
  SECTION),patch 头换 DEP-3 6 必填(Description/Origin/Upstream-Status/
  Applies-To/Maintainer/Last-Update)。
- **2026-07-20** v2.0 重构:精简到 `version-centric + patches/series` 模型,
  删除 `sync-manifest.py` / `whitelist-audit.py` / `build-perf.sh` / 派生 manifest 文件;
  patch 元数据迁到邮件式头;对齐 SUSE / Debian Quilt / Yocto 等业界方案。