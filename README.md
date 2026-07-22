# Kunpeng BoostKit Redis

> Patch overlay 治理规范。设计见 [docs/governance.md](./docs/governance.md)，schema 见 [docs/schemas.md](./docs/schemas.md)。

Kunpeng BoostKit Redis 在固定上游 Redis 版本基线上叠加 ARM/Kunpeng 平台优化 patch。v6.0 对齐 Buildroot `package/<name>/` 结构：目录即配置，文件系统即元数据。

## 快速开始

```bash
# 一键验证（仓根检查 + manifest + clean apply）
bash tools/verify.sh

# patch 头校验（DEP-3 6 必填 + 条件必填）
python3 .github/lint.py headers versions/*/

# manifest 校验 + DEP-3 全量
python3 .github/lint.py manifest versions/*/

# 一键全量
python3 .github/lint.py all versions/*/
```

**Feature 子集选择**：`ACTIVE_FEATURES` 环境变量选部分 feature，不传 = 全部：

```bash
# 全部 feature
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    versions/redis-7.0.15 \
    /tmp/build

# 只选 rdb-aof-fallback
ACTIVE_FEATURES="rdb-aof-fallback" bash tools/apply_patch.sh ... /tmp/build-a
```

## 目录结构

```
versions/redis-7.0.15/
├── manifest.yaml          # 上游 pin（3 字段）
├── kunpeng-hw-accel/      # feature 目录 = 含 .patch 的子目录
├── jemalloc-arm64/
└── rdb-aof-fallback/
```

## 文档

- **[docs/governance.md](./docs/governance.md)** — 设计原理 + 业界出处 + 工作流 + FAQ
- **[docs/schemas.md](./docs/schemas.md)** — 字段定义 + 校验矩阵
- **产品指南** — `docs/zh/` / `docs/en/`
- **[docs/research/openEuler-patch-mgmt.md](./docs/research/openEuler-patch-mgmt.md)** — openEuler 调研

## 贡献

1. 新增 patch → 放到对应 feature 目录 + 写 DEP-3 头（6 必填）
2. 跑本地 3 工具全绿（`verify.sh` + `lint.py headers` + `lint.py manifest`）
3. 开 PR → `ci.yml`（3 步）
4. Review → merge

## 许可证

- 本仓 overlay：Apache 2.0（[LICENSE.txt](./LICENSE.txt)）
- 上游 Redis：BSD-3-Clause（patch 头部保留）
- 产品文档：CC-BY 4.0（[docs/LICENSE](./docs/LICENSE)）
