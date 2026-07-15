# 白名单机制 — 规范 §4

> 配套章节:§1.3 / §1.4 / §4
> 配套工具:`tools/sync-manifest.py` + `tools/whitelist-audit.py`
> 配套生成物:`WHITELIST.yaml` + `docs/PATCHES-STATUS.md`

## 1. 触发条件(规范 §4.1)

patch 进入白名单(永久携带,不再追求上游合入)需满足任一:

- 上游明确 `rejected`,且团队评审同意保留
- patch 涉及鲲鹏 / 昇腾等强硬件绑定特性,上游无对应接口
- 安全 / 合规原因需在下游保留

## 2. 提交方式

**方式 A:在 version.yaml 直接标(SHOULD,推荐,规范 §4.2)**

```yaml
patches:
  - name: 0002-hw-dtoe-kunpeng.patch
    title: DTOE for Kunpeng
    type: project
    status: whitelisted
    upstream_pr: []
    whitelist_reason: |
      Kunpeng-specific DMA-to-engine HW feature,
      no upstream equivalent interface; reviewed by twwang@boostkit on 2026-06.
```

CI 抓 `status: whitelisted` + `whitelist_reason ≥30 字符` 自动登记到:
- `WHITELIST.yaml` (机器读)
- `docs/PATCHES-STATUS.md` (人读仪表盘)

**方式 B:补充提交评审材料(可选,推荐)**

对于影响范围大的白名单(≥3 个 version 携带、≥半年未变动),建议附 `docs/whitelist/<id>.md`:

```markdown
# WL-0002-hw-dtoe-kunpeng

- **决策日期**: 2026-06-15
- **决策人**: twwang@boostkit, chaosv598@boostkit
- **上游评估**: PR #12345 已关闭(rejected: 需上游配合 HW 抽象层重构)
- **替代方案**: 等待 Redis 8.x 网络栈重构(预计 2027 H1)
- **影响范围**: redis-7.0.15 / redis-7.2.4
- **季度评审**: 2026-09 复审是否仍需保留
```

## 3. 视图自动生成(规范 §4.3)

由 `python3 tools/sync-manifest.py --write` 生成:

| 文件 | 用途 | 字段来源 |
|---|---|---|
| `WHITELIST.yaml` | 机器读白名单视图 | version.yaml `status: whitelisted` + `whitelist_reason` |
| `docs/PATCHES-STATUS.md` | 人读状态仪表盘 | 所有 patch 状态 + reason 摘要 |
| `PATCHES.yaml` | 仓内 patch 单一真相源 | 所有 patch 跨版本聚合 |

## 4. 字段复用规则(规范 §1.4)

`whitelist_reason` 字段**同时承担两个语义**:

| `status` 取值 | `whitelist_reason` 含义 | 必填条件 |
|---|---|---|
| `whitelisted` | 永久携带的理由 | 必填,≥30 字符 |
| `rejected` | 上游拒绝原因 | 必填,任意长度 |

`status: pending` / `submitted` / `accepted` 时此字段可空。

## 5. 季度评审(规范 §4.4)

team lead 每季度跑:

```bash
python3 tools/whitelist-audit.py           # 打印报告
python3 tools/whitelist-audit.py --strict  # CI gate,reason <30 字符项 fail
```

输出示例:

```
=== 白名单审计 (规范 §4.4) ===
白名单 patch 数: 1
reason 字数下限: 30
陈旧阈值: 携带 ≥180 天未评估

patch.name                                              跨版本                  reason 长度  verdict
----------------------------------------------------------------------------------------------------
0002-perf-kunpeng-adapt-dtoe.patch                       7.0.15                            115  ⚠ 待季度评审 (建议 2026-07-15)
```

## 6. 评审结论回写

评审后:
- 修改 `docs/whitelist/<id>.md` 的"季度评审跟踪"表格
- 如决定移除白名单状态,改 `status: whitelisted` → `pending`(从 PATCHES.yaml 自动消失)
- 如续期,只需确保 `whitelist_reason` 内容继续反映当前理由

## 7. 为什么不独立维护 `WHITELIST.yaml`?

- **单一真相源在 version.yaml**(开发者契约)
- WHITELIST.yaml 由 sync-manifest 自动派生,避免双写不一致
- 评审材料 `docs/whitelist/<id>.md` 是可选补充,留给人写决策依据
- 业务 PR 不需要碰 WHITELIST.yaml(规范 §10 YAGNI)
