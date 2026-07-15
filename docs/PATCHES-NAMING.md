# Patch 文件命名规范

> 强制级别:**MUST** = 违反即 CI 拒收 · **SHOULD** = 违反需评审说明
> 规范章节:§3.1

## 1. 格式

```text
NNNN-{category}-{topic}[-({suffix})].patch
```

## 2. 规则

| 段 | 规则 | 示例 |
|---|---|---|
| `NNNN` | 4 位序号,**version 内唯一** | `0001` |
| `category` | `hw` \| `perf` \| `sec` \| `compat` \| `feature` | `hw` |
| `topic` | kebab-case,≤30 字符 | `iouring-kunpeng` |
| `suffix` | 可选,标记 backport 范围 | `-on-6.0.15-6.0.20` |

## 3. category 取值(规范 §3.1)

| category | 含义 | 例子 |
|---|---|---|
| `hw` | 硬件适配 (Kunpeng / 昇腾 / NIC) | `0001-hw-iouring-kunpeng` |
| `perf` | 性能优化 | `0002-perf-dtoe-kunpeng` |
| `sec` | 安全补丁 | `0010-sec-cve-2025-1234` |
| `compat` | 兼容 / 适配层 | `0011-compat-glibc-2.28` |
| `feature` | 新功能 | `0020-feature-stream-block` |

## 4. version 目录名(规范 §3.2)

格式 `redis-<major>.<minor>.<patch>`,小写:

```
versions/redis-7.0.15/
versions/redis-7.2.4/
versions/redis-6.0.20/
```

禁止:`v7.0.15` / `redis-7` / `Redis-7.0.15`。

## 5. 正例

```
0001-hw-kunpeng-adapt-iouring.patch
0002-perf-kunpeng-adapt-dtoe.patch
0003-perf-jemalloc-arm64-pointer-tag-and-gc.patch
0004-perf-rdb-fallback-aof.patch
0001-hw-kunpeng-adapt-iouring-on-6.0.15-6.0.20.patch
```

## 6. 反例 (CI 拒收)

| 错误 | 原因 |
|---|---|
| `0001-xxx.patch` | category 缺失 |
| `some_feature.patch` | 无序号 |
| `1.patch` | 序号不足 4 位 |
| `0001-HW-iouring.patch` | category 大写 |
| `0001_hw_iouring_kunpeng.patch` | 用 `_` 而非 `-` |
| `0001-fix-iouring-kunpeng.patch` | category 不在允许列表 (§3.1) |
| `0001-hw-iouring kunpeng.patch` | topic 含空格 |

## 7. 跨版本命名(SHOULD)

同一 logical patch 在多版本出现时,`topic` 保持一致,`suffix` 标记版本范围:

```
# 主版本
0001-hw-kunpeng-adapt-iouring.patch

# backport 到 6.0.x
0001-hw-kunpeng-adapt-iouring-on-6.0.15-6.0.20.patch
```

CI 校验:每个 `version.yaml` 的 `patches[].name` 必须对应 `patches/<name>.patch` 文件(规范 §2.2 合并算法末尾)。
