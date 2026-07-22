## 变更摘要

- 上游版本: `<e.g. redis-7.0.15>`
- feature: `<affected feature name(s)>`
- 类型: `new patch | update metadata | docs | tools`

## 本地验证（必做）

- [ ] `bash tools/verify.sh` 通过
- [ ] `python3 .github/lint.py headers versions/*/` 通过
- [ ] `python3 .github/lint.py manifest versions/*/` 通过

## Patch 合规（新增/修改 patch 时必填）

- [ ] DEP-3 头 6 必填字段齐全（Description / Origin / Upstream-Status / Applies-To / Maintainer / Last-Update）
- [ ] From / Subject / Signed-off-by 已填
- [ ] 条件必填按 Upstream-Status 补全（Submitted → Upstream-PR, Accepted → Upstream-Commit, Rejected → Whitelist-Reason）
- [ ] feature 目录与 manifest.yaml 声明一致，depends 引用有效，无环依赖
