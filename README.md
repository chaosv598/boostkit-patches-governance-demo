# Kunpeng BoostKit Redis

> Patch overlay 治理规范 demo。设计文档见 [docs/governance.md](./docs/governance.md)，schema 定义见 [docs/schemas.md](./docs/schemas.md)。

Kunpeng BoostKit Redis 在固定上游 Redis 版本基线上叠加 ARM/Kunpeng 平台优化 patch，采用 **version-centric + feature 声明** 模型，集合 Yocto/DEP-3/Buildroot/OpenWrt/Kconfig 5 家业界方案之长。

## 快速开始

```bash
# 一键验证（仓根检查 + upstream.yaml schema + clean clone + apply）
bash tools/verify.sh

# patch 头校验（DEP-3 6 必填 + 条件必填）
python3 .github/lint.py headers versions/*/patches/

# features.yaml 校验（schema + depends + 孤儿检测）
python3 .github/lint.py features versions/*/patches/

# 或一键全量
python3 .github/lint.py all versions/*/patches/
```

**Feature 组合**：客户用 `ACTIVE_FEATURES` 环境变量选特性子集，`apply_patch.sh` 自动解析依赖：

```bash
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build

# 只选部分特性
ACTIVE_FEATURES="rdb-aof-fallback" bash tools/apply_patch.sh ... --features ... /tmp/build-a
```

## 设计原理

详见文档：
- **[docs/governance.md](./docs/governance.md)** — 设计原理 + 5 家业界出处 + 工作流 + 常见操作 + FAQ
- **[docs/schemas.md](./docs/schemas.md)** — YAML/header 字段权威定义 + 校验矩阵
- **产品指南** — `docs/zh/` (中文) / `docs/en/` (英文)：特性使用说明、版本配套、构建步骤
- **[docs/research/openEuler-patch-mgmt.md](./docs/research/openEuler-patch-mgmt.md)** — openEuler patch 管理调研与本仓对比

## 贡献

PR-only 流程：

1. 新增 patch → 放 `patches/features/<feature>/` + 写 DEP-3 头（6 必填）+ 在 `features.yaml` 加 entry
2. 跑本地 3 工具全绿（`verify.sh` + `lint.py headers` + `lint.py features`）
3. 开 PR → 触发 `ci.yml` 3 步 + `build-perf.yml` matrix
4. 维护者 review → merge

## 许可证

- 本仓 patch overlay：Apache 2.0（[LICENSE.txt](./LICENSE.txt)）
- 上游 Redis：BSD-3-Clause（各 patch 头部保留）
- 产品文档：CC-BY 4.0（[docs/LICENSE](./docs/LICENSE)）
