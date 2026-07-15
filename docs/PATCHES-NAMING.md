# Patch 文件命名规范

> 强制级别:**MUST** = 违反即 CI 拒收 · **SHOULD** = 违反需评审说明
> 规范章节:§6

## 1. 格式

```text
<NNNN>-<category>-<topic>.patch
```

## 2. 规则

- `NNNN` MUST 为四位连续序号,从 `0001` 起,**version 内唯一**
- `category` MUST 只允许:`fix` | `feat` | `perf` | `hw` | `security` | `compat`
- `topic` MUST 使用小写字母、数字和连字符,SHOULD ≤40 字符
- `version.yaml.patches[].name` 不包含 `.patch` 后缀
- patch 邮件 Subject、Signed-off-by、代码格式、测试要求 MUST 符合目标上游社区
- patch MUST 通过 `git apply --check` 和 whitespace 检查

## 3. category 取值

| category | 含义 | 例子 |
|---|---|---|
| `fix` | bug 修复 | `0001-fix-rdb-fallback-aof` |
| `feat` | 新功能 | `0020-feat-stream-block` |
| `perf` | 性能优化 | `0002-perf-dtoe-kunpeng` |
| `hw` | 硬件适配 (Kunpeng / 昇腾 / NIC) | `0001-hw-kunpeng-adapt-iouring` |
| `security` | 安全补丁 | `0010-security-cve-2025-1234` |
| `compat` | 兼容 / 适配层 | `0011-compat-glibc-2.28` |

## 4. 安装顺序与编号

- 规范 §5:`patches[]` 数组顺序 MUST 是唯一 apply 顺序
- `NNNN` MUST 与数组位置一致,从 `0001` 连续递增
- 调整安装顺序 MUST 同步调整数组顺序和文件编号
- CI MUST 检查数组、编号、文件和依赖顺序的一致性

## 5. 跨版本命名 (SHOULD)

backport 到旧版本时,推荐加后缀 `-on-<range>`:

```
0001-hw-kunpeng-adapt-iouring.patch                       # 主版本
0001-hw-kunpeng-adapt-iouring-on-6.0.15-6.0.20.patch      # backport
```

但注意:不同 version 的 patch name **不**要求全局唯一,各 version 内部独立编号即可。

## 6. 正例

```
0001-hw-kunpeng-adapt-iouring.patch
0002-perf-kunpeng-adapt-dtoe.patch
0003-perf-jemalloc-arm64-pointer-tag-and-gc.patch
0004-perf-rdb-fallback-aof.patch
0001-hw-kunpeng-adapt-iouring-on-6.0.15-6.0.20.patch
```

## 7. 反例 (CI 拒收)

| 错误 | 原因 |
|---|---|
| `0001-xxx.patch` | category 缺失 |
| `some_feature.patch` | 无序号 |
| `1.patch` | 序号不足 4 位 |
| `0001-feat-iouring kunpeng.patch` | topic 含空格 |
| `0001-Fix-iouring.patch` | category 大写 |
| `0001_fix_iouring.patch` | 用 `_` 而非 `-` |
| `0001-bugfix-iouring.patch` | category=bugfix 不在允许列表 |

## 8. version 目录名

格式 `redis-<major>.<minor>.<patch>`,MUST 小写:

```
versions/redis-7.0.15/
versions/redis-7.2.4/
versions/redis-6.0.20/
```

禁止:`v7.0.15` / `redis-7` / `Redis-7.0.15`。
