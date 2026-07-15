## 改了什么

- 上游版本: `<v, 例 redis-7.0.15>`
- patch name: `<NNNN-{category}-{topic}.patch>`
- 类型: `<new patch / update metadata / docs / tools>`

## 验证(规范 §7.2 / §9.2 必跑)

- [ ] `bash tools/verify.sh` 通过
- [ ] `bash tools/upstream-lint.sh versions/<v>/patches/<name>.patch` 通过
- [ ] 已 `grep -nE ' +$' versions/<v>/patches/<name>.patch` 无 trailing whitespace
- [ ] 已 `grep -nP '\r$' versions/<v>/patches/<name>.patch` 无 CRLF
- [ ] 已 `git apply --check` 在 clean upstream @ commit 上通过
- [ ] CI 通过(PATCHES.yaml / WHITELIST.yaml 与 version.yaml 一致)

## 字段填齐(规范 §1.3 / §1.4)

- [ ] `version_id` / `description` / `owner` 填齐
- [ ] `upstream_base.{repo, version, commit}` 填齐(commit 40 位 SHA)
- [ ] `patches[].{name, title, owner, type, status, dependence}` 填齐

## 上游跟踪(按 status 必填,§1.4)

- [ ] `status: submitted` → 已填 `upstream_pr[]` (上游 PR 链接)
- [ ] `status: accepted` → 已填 `upstream_pr[]` 且备注 merged commit
- [ ] `status: whitelisted` → 已填 `whitelist_reason` ≥30 字符
- [ ] `status: rejected` → 已填 `whitelist_reason` (复用字段填拒绝原因)

## 命名规范(§3.1)

- [ ] 文件名匹配 `^[0-9]{4}-(hw|perf|sec|compat|feature)-[a-z0-9-]+\.patch$`
- [ ] 不与同 version 内其他 patch 重名(序号 NNNN 唯一)

## 影响

- 影响的版本: `<v>`
- 是否触发上游 PR: `<yes / no>`
- 上游 PR 链接(如有): `<URL>`
- 是否新增白名单: `<yes / no>`(若 yes,确认 whitelist_reason ≥30 字符)

## CI 预期(规范 §8)

- [ ] ci.yml 6 阶段全过(sync-check / verify / upstream-lint / whitelist-audit)
- [ ] drift 时 CI 自动 commit 修复(`manifest: auto-sync from version.yaml [skip ci]`)
- [ ] **不需要**手改 PATCHES.yaml / WHITELIST.yaml(规范 §10 YAGNI)
