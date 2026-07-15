# Patch Manifest 生成 — 规范 §9

> 配套章节:§9.1 / §9.2
> 配套工具:`tools/sync-manifest.py`
> 配套生成物:`out/patches-manifest.json`

## 1. 关键原则 (规范 §9.1)

1. **Manifest MUST 由 CI 自动生成** — 不得要求业务 PR 维护
2. **Manifest MUST 作为 CI artifact 和 patchset 发布附件保存**
3. **Manifest MUST NOT 由业务人工编辑**
4. **Manifest MUST NOT 由 CI commit 或 push 回业务分支**
5. **普通 PR MUST NOT 因仓库中没有已提交 Manifest 而失败**
6. **发布系统和组织级治理系统只消费生成结果,不回写业务仓**

## 2. 输出位置

```
out/patches-manifest.json
```

**禁止**:
- 写在仓根 (会污染业务仓)
- 提交回业务分支 (会引入合并冲突)
- 跟代码混在一起 (与源码生命周期不同)

## 3. Manifest 内容 (规范 §9.2)

```json
{
  "manifest_version": 1,
  "generated_at": "2026-07-15T...",
  "generator": "tools/sync-manifest.py",
  "source": {
    "repository": "git@github.com:boostkit/redis-patches.git",
    "branch": "master",
    "commit": "<40-char SHA>"
  },
  "summary": {
    "version_count": 2,
    "patch_count": 5
  },
  "versions": [
    {
      "version_id": "redis-7.0.15",
      "maintained_status": "maintained",
      "planned_eol": "2027-06-30",
      "release_owner": "chaosv598@boostkit",
      "upstream": {
        "repo": "https://github.com/redis/redis.git",
        "tag": "7.0.15",
        "commit": "f35f36a265403c07b119830aa4bb3b7d71653ec9"
      },
      "validation": { ... },
      "patches": [
        {
          "sequence": 1,
          "name": "0001-hw-kunpeng-adapt-iouring",
          "owner": "twwang@boostkit",
          "type": "ecological",
          "status": "submitted",
          "upstream_pr": "https://github.com/redis/redis/pull/12345",
          "test_profile": "redis-kraio-arm64",
          "dependence": [],
          "content_sha256": "ab12...",
          "exception": null
        },
        {
          "sequence": 2,
          "name": "0002-perf-kunpeng-adapt-dtoe",
          "owner": "twwang@boostkit",
          "type": "project",
          "status": "accepted",
          "upstream_pr": "",
          "test_profile": "redis-dtoe-arm64",
          "dependence": [],
          "content_sha256": "cd34...",
          "exception": {
            "reason": "...",
            "approved_by": ["boostkit-component-maintainer", "boostkit-architecture-owner"],
            "approved_at": "2026-07-15",
            "review_due_at": "2026-10-13",
            "expires_at": "2027-01-11",
            "required_check": "self-hosted/redis-dtoe-arm64",
            "evidence_max_age_days": 30
          }
        }
      ]
    }
  ]
}
```

## 4. 唯一键

Patch 唯一键 MUST 用:
```
<repository>/<source-branch>/<version-id>/<patch-name>
```

不得按跨版本同名 patch 自动合并条目。组织级视图 MAY 按名称或内容哈希聚合展示,但 MUST 保留原始分支和版本记录。

## 5. CI 集成

```yaml
# .github/workflows/ci.yml
- name: Generate manifest
  run: bash tools/sync-manifest.py
- name: Upload manifest
  if: always()
  uses: actions/upload-artifact@...
  with:
    name: patches-manifest
    path: out/patches-manifest.json
    retention-days: 90
```

Manifest 作为 PR artifact **只读**,不参与 git diff,不引发 reviewer 关注。

## 6. 发布系统消费

发布流程:
1. CI 生成 `out/patches-manifest.json` 作为 artifact
2. 发布系统下载 artifact
3. 校验内容 (版本号、SHA、patch sha256 与 git 状态)
4. 把 manifest 附加到 release tag (例如 `redis-7.0.15-patchset.3`)

```bash
# 发布脚本示例
gh run download <run-id> -n patches-manifest
jq -r '.versions[] | .patches[] | "\(.name) \(.content_sha256)"' \
  out/patches-manifest.json
```

## 7. 本地调试

```bash
# 打印到 stdout
bash tools/sync-manifest.py --print

# 写到自定义路径
bash tools/sync-manifest.py --out /tmp/manifest.json
```

## 8. 与 PATCHES.yaml 的区别

旧方案(已弃用):仓根 `PATCHES.yaml` + `WHITELIST.yaml` 手动维护。
- ✗ 业务 PR 需重复维护,违反规范 §1 治理原则 5
- ✗ CI 自动 commit 易引发合并冲突
- ✗ 跟代码同生命周期,git log 噪声大

新方案(当前):
- ✓ 业务 PR 0 改动
- ✓ 单一真相源 = version.yaml
- ✓ Manifest 是只读 artifact,跟代码解耦
