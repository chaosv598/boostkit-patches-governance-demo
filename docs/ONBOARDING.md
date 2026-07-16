# 新人 Onboarding —— 10 分钟走通 PR 全流程

> **本文档**:5 分钟铺垫 + 5 分钟实操,目标 = 让新人敢提第一个 PR。
> **手册正文**:`docs/DEVELOPER-GUIDE.md`(字段、流程、工具完整说明)。
> **历史版本**:`docs/_archive/simplify-v3/ONBOARDING.md`(已弃用,讲旧 1 工具/3 状态叙事)。

---

## 0. 5 分钟铺垫:5 件事先记牢

1. **唯一手写入口**:`versions/<v>/version.yaml` + `versions/<v>/patches/<name>.patch`
2. **派生物不动手**:`PATCHES.yaml` / `WHITELIST.yaml` / `docs/PATCHES-STATUS.md` 全由 CI 写
3. **本地必跑 4 工具**:`verify.sh` + `sync-manifest.py --check` + `whitelist-audit.py --strict` + `upstream-lint.sh`
4. **CI 6 阶段全绿才允许 merge**;build-perf 改动 patch 才触发
5. **5 状态机**:`pending` / `submitted` / `accepted` / `rejected` / `whitelisted`

---

## 1. 准备环境(2 分钟)

```bash
git clone https://github.com/chaosv598/boostkit-patches-governance-demo.git
cd boostkit-patches-governance-demo
pip install pyyaml
bash tools/verify.sh              # 应看到全部 ✓
python3 tools/sync-manifest.py --check   # 应看到 sync-manifest 一致
```

期望两个都退出码 0。如果 verify.sh 报 `apply 失败(单 patch)` 是正常的 warning,不阻塞。

---

## 2. 5 分钟实操:改一个 patch 的状态

**目标**:把 `redis-7.0.15/0003-perf-jemalloc-arm64-pointer-tag-and-gc` 从 `submitted` 改成 `accepted`(假装上游已 merge)。

### 2.1 分支

```bash
git checkout master && git pull
git checkout -b docs/onboarding-demo
```

### 2.2 改 yaml(唯一手写入口)

打开 `versions/redis-7.0.15/version.yaml`,找到 0003 那一条:

```diff
   - name: 0003-perf-jemalloc-arm64-pointer-tag-and-gc
     title: Adapt jemalloc 5.2.1 ARM64 pointer-tag and GC strategy optimize
     owner: yinbin@boostkit
     type: ecological
-    status: submitted
+    status: accepted
     upstream_pr:
       - https://github.com/redis/jemalloc/pull/9876
```

### 2.3 本地校验(3 工具必跑)

```bash
bash tools/verify.sh              # 字段 + 一致性 + apply
python3 tools/sync-manifest.py --check    # drift 检测
python3 tools/whitelist-audit.py --strict # 白名单审计(本场景无关,会绿)
```

期望:`verify.sh` 全 ✓;`sync-manifest --check` 报 `✓ ... 与 version.yaml 一致`。

### 2.4 commit + push + PR

```bash
git add versions/redis-7.0.15/version.yaml
git commit -m "docs(0003): mark as accepted (onboarding demo)"
git push -u origin docs/onboarding-demo
gh pr create --title "docs(0003): mark as accepted (onboarding demo)" \
  --body-file .github/PULL_REQUEST_TEMPLATE.md
```

### 2.5 等 CI

PR 页面右下角 GitHub Actions 应跑 6 阶段,全部 ✅。merge 后 PATCHES.yaml 会自动更新(`sync-manifest` 在 post-merge 也会跑)。

**完成**。🎉 你已走完完整 PR 流程。

---

## 3. 接下来深入

| 想了解 | 读 |
|---|---|
| 字段完整说明 / 5 状态机 / 5 常见场景 / 失败排查 | **`docs/DEVELOPER-GUIDE.md`** |
| 治理设计原理(为什么 5 工具 / 5 状态) | `docs/GOVERNANCE.md` |
| 元数据格式 + 4 个常见场景 | `docs/patch-lifecycle.md` |
| CI 配置 + build-perf 链路 | `docs/ci-github-actions.md` |
| sync-manifest 派生协议 | `docs/MANIFEST-PROCESS.md` |
| 白名单 / Exception 机制 | `docs/WHITELIST-PROCESS.md` / `docs/EXCEPTION-PROCESS.md` |
| 文件名规范 | `docs/PATCHES-NAMING.md` |
| 给 AI 助手的背景 | `CLAUDE.md` |

---

## 4. 完成清单

- [ ] 克隆仓 + 跑 4 工具看到绿
- [ ] 改一个 patch 的 status,跑 verify + sync-manifest --check 看到绿
- [ ] commit + push + 开 PR + 等 CI 6 阶段全绿
- [ ] squash merge
- [ ] 跑 sync-manifest --check 在 master 上看到 PATCHES.yaml 已自动更新