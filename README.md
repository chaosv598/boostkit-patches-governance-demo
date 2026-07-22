# Kunpeng BoostKit Redis

> Patch overlay 治理规范。设计见 [docs/governance.md](./docs/governance.md)，schema 见 [docs/schemas.md](./docs/schemas.md)。

Kunpeng BoostKit Redis 在固定上游 Redis 版本基线上叠加 ARM/Kunpeng 平台优化 patch，采用 **version-centric + feature 声明** 模型（v6.0 起对齐 Buildroot `package/<name>/` 结构）。

## 快速开始

```bash
# 一键验证（仓根检查 + manifest.yaml schema + clean clone + apply）
bash tools/verify.sh

# patch 头校验（DEP-3 6 必填 + 条件必填）
python3 .github/lint.py headers versions/*/

# manifest.yaml 校验（depends + 目录一致性 + 孤儿检测）
python3 .github/lint.py manifest versions/*/

# 或一键全量
python3 .github/lint.py all versions/*/
```

**Feature 组合**：`ACTIVE_FEATURES` 选特性子集，`apply_patch.sh --manifest` 自动解析依赖：

```bash
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --manifest versions/redis-7.0.15/manifest.yaml \
    versions/redis-7.0.15 \
    /tmp/build

# 只选部分特性
ACTIVE_FEATURES="rdb-aof-fallback" bash tools/apply_patch.sh ... --manifest ... /tmp/build-a
```

## 设计原理

详见文档：
- **[docs/governance.md](./docs/governance.md)** — 设计原理 + 业界出处 + 工作流 + FAQ
- **[docs/schemas.md](./docs/schemas.md)** — YAML/header 字段权威定义 + 校验矩阵
- **产品指南** — `docs/zh/` (中文) / `docs/en/` (英文)
- **[docs/research/openEuler-patch-mgmt.md](./docs/research/openEuler-patch-mgmt.md)** — openEuler 调研

## 贡献

PR-only 流程：

1. 新增 patch → 放到对应 feature 目录下 + 写 DEP-3 头（6 必填）
2. 跑本地 3 工具全绿（`verify.sh` + `lint.py headers` + `lint.py manifest`）
3. 开 PR → 触发 `ci.yml` 3 步
4. 维护者 review → merge

## 许可证

- 本仓 patch overlay：Apache 2.0（[LICENSE.txt](./LICENSE.txt)）
- 上游 Redis：BSD-3-Clause（各 patch 头部保留）
- 产品文档：CC-BY 4.0（[docs/LICENSE](./docs/LICENSE)）
