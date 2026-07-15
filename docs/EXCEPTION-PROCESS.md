# 异常 (Exception) 机制 — 规范 §8

> 配套章节:§7.2 / §8 / §12
> 配套工具:`tools/whitelist-audit.py`
> 配套生成物:`out/patches-manifest.json` (含 `exception` 块)

## 1. 什么是 Exception

Exception 是 `type: project` + `status: accepted` 的 patch 在 version.yaml 内联的**有期限白名单**。

区别于生态 patch 的"已合并上游",project patch 是 BoostKit **下游维护**且**不追求上游合入**的 patch,例如:

- KRAIO (Kunpeng Redis Asynchronous I/O)
- DTOE (DMA-to-Engine 鲲鹏专属网络优化)
- 强硬件绑定 / 安全合规保留的 patch

Exception 是**唯一**的白名单形式,本仓**不**维护独立的 `WHITELIST.yaml` 等总白名单文件 — 业务 PR 无需重复维护。

## 2. 必填字段 (规范 §8)

```yaml
patches:
  - name: 0002-perf-kunpeng-adapt-dtoe
    type: project
    status: accepted
    exception:
      reason: |
        DTOE requires Kunpeng ARM64 hardware, openEuler kernel support,
        and dedicated DTOE libraries. No upstream equivalent abstraction.
      approved_by:                       # 至少 2 个不同角色,不能只有 patch owner
        - boostkit-component-maintainer
        - boostkit-architecture-owner
      approved_at: 2026-07-15             # 批准日期
      review_due_at: 2026-10-13           # 复审日 (≤90 天一次)
      expires_at: 2027-01-11              # 到期日 (≤180 天)
      required_check: self-hosted/redis-dtoe-arm64   # 必需的 self-hosted check
      evidence_max_age_days: 30           # 验证证据最大有效天数 (≤30)
```

## 3. 时效约束

| 约束 | 阈值 | 来源 |
|---|---|---|
| 复审周期 | ≤90 天 | §8 |
| 单次批准最长 | ≤180 天 | §8 |
| 硬件 evidence 最大有效期 | ≤30 天 | §8 |
| approved_by 角色数 | ≥2 不同角色 | §8 |

CI 校验:
```bash
bash tools/whitelist-audit.py --strict    # 异常项 exit 1
```

## 4. 过期行为 (规范 §8 / §12)

- **expires_at < today** → 涉及该 patch 的 required check **MUST fail**
- **review_due_at < today** → 复审超期,owner 需立即复审
- **evidence 超 evidence_max_age_days** → 视为过期,需重新跑硬件 check

过期处理:
- owner MUST 续期 (更新 `exception.*` 字段)
- 或移除 patch (从 `patches[]` 删除 + 删 `.patch` 文件)
- 或将版本标记为 EOL (改 `support.status: eol`)

## 5. 不得豁免项 (规范 §8 末尾)

Exception 不得豁免以下任一:

1. YAML 和 patch 文件一致性
2. 精确 upstream repo/tag/SHA
3. clean apply
4. hosted build
5. 不依赖专用硬件的上游 UT
6. 基础功能测试
7. 对应硬件环境的发布前验证

即:Exception 只豁免"上游合入要求",**不**豁免验证。

## 6. 流程图

```
patch 提议 type=project
       ↓
申请 Exception (填齐 7 个必填字段)
       ↓
两个不同角色 review + 批准
       ↓
version.yaml 提交 + PR
       ↓
CI 跑 verify.sh + whitelist-audit.py --strict
       ↓
每 90 天:复审 + 更新 approved_at/review_due_at/expires_at
       ↓
每 180 天:必须续期或移除
       ↓
每 30 天:硬件 evidence 重新跑 (在 self-hosted runner)
```

## 7. 与 ecological patch 的区别

| 维度 | ecological | project |
|---|---|---|
| 目标 | 推进上游合入 | BoostKit 下游维护 |
| status: accepted 含义 | PR 已 merge upstream | Exception 有效 |
| 长期归宿 | 上游 merge 后可移除 | 永久 (每 180 天续期) |
| 必备字段 | `pr` URL | `exception` 块 |
| 复审 | 不强制 | 90 天 |
| 硬件 check | 不强制 | 30 天 evidence 必跑 |
