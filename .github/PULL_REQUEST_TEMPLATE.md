## 改了什么

- 上游版本: `<v, 例 redis-7.0.15>`
- patch name: `<NNNN-category-topic>`
- 类型: `<new patch / update metadata / docs / tools>`

## version.yaml 字段(必填,规范 §4.2)

- [ ] `version_id` / `description` / `owner` 填齐
- [ ] `support.{status, planned_eol, release_owner}` 填齐
- [ ] `upstream_base.{repo, version, commit}` 填齐(commit 是 40 位 SHA)
- [ ] `validation.upstream_commands` 填齐
- [ ] `patches[].{name, title, owner, type, status, dependence}` 填齐

## Patch 字段(规范 §4.2 / §4.4)

- [ ] `name` — 与 `patches/<name>.patch` 文件名一致
- [ ] `type` ∈ `{ecological, project}`
- [ ] `status` ∈ `{pending, submitted, accepted}`
- [ ] `dependence` — 可空数组 `[]`,引用的 patch 须在数组前面
- [ ] `pr` 必填:**status=submitted/accepted** 时是真实可访问的 PR URL,**禁止 `/pull/TBD`**
- [ ] `test_profile` 填齐

## Exception(仅 type=project + status=accepted,规范 §8)

- [ ] `exception.reason` 必填
- [ ] `exception.approved_by` 至少 **2 个不同角色**,不能只有 patch owner
- [ ] `exception.approved_at` / `review_due_at` / `expires_at` 填齐
- [ ] `expires_at - approved_at` ≤ **180 天**
- [ ] `evidence_max_age_days` ≤ **30 天**
- [ ] `required_check` 填 self-hosted 标签

## 安装顺序与编号(规范 §5)

- [ ] `patches[]` 数组顺序 = 唯一 apply 顺序
- [ ] `NNNN` 与数组位置一致,从 `0001` 连续递增
- [ ] 调整顺序时**同步**调整数组顺序和文件编号

## 命名规范(规范 §6,见 docs/PATCHES-NAMING.md)

- [ ] 文件名匹配 `^[0-9]{4}-(fix|feat|perf|hw|security|compat)-[a-z0-9-]+\.patch$`
- [ ] 不与同 version 内其他 patch 重名

## 上游跟踪(按 status 必填)

- [ ] `pending` — `pr` 可空,但 30 天后需升级
- [ ] `submitted` — `pr` 是真实可访问的 open PR
- [ ] `accepted` + ecological — PR 已 merge upstream
- [ ] `accepted` + project — `exception` 块有效

## 验证(规范 §10,本地必跑)

- [ ] `bash tools/verify.sh` 通过
- [ ] `bash tools/sync-manifest.py` 生成 `out/patches-manifest.json` 成功
- [ ] `bash tools/whitelist-audit.py --strict` 通过
- [ ] `bash tools/upstream-lint.sh versions/<v>/patches/<name>.patch` 通过

## CI 预期(规范 §11.1)

- [ ] `ci.yml` 9 阶段全过(metadata/schema → manifest → upstream → apply → lint → build → UT → smoke → upload)
- [ ] 硬件 patch (`test_profile: redis-dtoe-arm64` 等) 在 self-hosted runner 跑通
- [ ] `patches-manifest` artifact 上传成功(retention 90 天)
- [ ] **不需要**改总 Manifest (规范 §1 原则 5)
- [ ] **不需要**碰其他 version 的 `version.yaml`
