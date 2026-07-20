# Redis 网络优化特性

## 项目品牌名称

Kunpeng BoostKit Redis

## 项目介绍

Kunpeng BoostKit Redis 是基于上游 Redis 的 patch overlay,在固定上游版本基线上叠加
BoostKit 团队维护的 ARM/Kunpeng 平台优化 patch。

**核心模型**:version-centric + 显式 `patches/series`(对齐 SUSE / Debian Quilt /
Yocto OpenEmbedded / ungoogled-chromium 等业界主流方案,见
[docs/governance.md §2](./docs/governance.md#2-业界出处))。

## 目录结构

```text
boostkit-patches-governance-demo/
├── README.md / README_en.md            # 本文件
├── LICENSE.txt                          # 上游 license 全文
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/
│       ├── ci.yml                       # 3 步:verify + patch 头 lint + series lint
│       └── build-perf.yml               # matrix: clean clone + make + memtier
├── tools/
│   └── verify.sh                        # 仓根禁放 + upstream.yaml + clean apply series
├── docs/
│   ├── governance.md                    # ★ 设计原理 + 业界出处
│   ├── version-yaml-spec.md             # ★ 字段权威定义
│   └── (产品指南 zh/en 保留)
└── versions/
    └── <upstream-id>/                   # 例如 redis-7.0.15
        ├── upstream.yaml                # 上游基线
        └── patches/
            ├── series                   # ★ 唯一权威顺序
            └── *.patch                  # RFC822 邮件式头 + diff
```

## 快速开始

### 1. 上游基线 + patch 顺序一目了然

`versions/redis-7.0.15/upstream.yaml`:

```yaml
upstream:
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: f35f36a265403c07b119830aa4bb3b7d71653ec9
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
# 1. 仓根干净 + upstream.yaml schema + clean clone + 按 series apply
bash tools/verify.sh

# 2. patch 邮件式头 schema(对齐 Yocto Upstream-Status)
python3 .github/lint_patch_headers.py versions/*/patches/

# 3. series 一致性(无孤儿 + 无重复)
python3 .github/lint_series.py versions/*/patches/
```

### 3. 在 Kunpeng 上构建

```bash
# 按 governance.md §3.2 "本地复跑" 章节的步骤
# 1) clean clone + apply series
git clone --depth=1 https://github.com/redis/redis
cd redis
git fetch origin f35f36a265403c07b119830aa4bb3b7d71653ec9
git checkout f35f36a265403c07b119830aa4bb3b7d71653ec9
while read p; do
  [ -z "$p" ] && continue
  [[ "$p" == \#* ]] && continue
  git apply "../versions/redis-7.0.15/patches/$p"
done < ../versions/redis-7.0.15/patches/series

# 2) build
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

业界出处:
- Quilt / Debian `debian/patches/series` — 自上而下顺序清单
- SUSE `kernel-source/series.conf` — 显式清单 + `Git-commit` 元数据校验
- Yocto/OpenEmbedded `Upstream-Status` 字段 — 8 状态语义对齐
- ungoogled-chromium `patches/series` — version pin ↔ patches 分离
- openEuler `apply-patches` — series + guards(未来扩展)

## 贡献

只接受 PR,不接受直推 master。流程:

1. 新增 patch → 修改 `patches/series` 一行 + 写邮件式头
2. 跑本地 3 工具全绿
3. 开 PR,触发 `ci.yml` 3 步 + `build-perf.yml` matrix
4. 维护者 review → merge

## 许可证

- 本仓 patch overlay:Apache 2.0(见 [LICENSE.txt](./LICENSE.txt))
- 上游 Redis:BSD-3-Clause(各 patch 头部保留原始 license)
- 产品文档:CC-BY 4.0(见 [docs/LICENSE](./docs/LICENSE))

## 变更通知

- **2026-07-20** v2.0 重构:精简到 `version-centric + patches/series` 模型,
  删除 `sync-manifest.py` / `whitelist-audit.py` / `build-perf.sh` / 派生 manifest 文件;
  patch 元数据迁到邮件式头;对齐 SUSE / Debian Quilt / Yocto 等业界方案。