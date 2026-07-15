#!/usr/bin/env python3
"""
sync-manifest —— version.yaml → out/patches-manifest.json 自动生成

依据治理规范 §9:
  - Manifest MUST 由 CI 自动生成,不得要求业务 PR 维护
  - Manifest MUST 作为 CI artifact 和 patchset 发布附件保存
  - Manifest MUST NOT 由 CI commit 或 push 回业务分支
  - Manifest MUST NOT 因仓库中没有已提交 Manifest 而让普通 PR 失败

用法:
  bash tools/sync-manifest.py                    # 默认写到 out/patches-manifest.json
  bash tools/sync-manifest.py --out /path/x.json # 自定义输出
  bash tools/sync-manifest.py --print            # 打印到 stdout
"""
import argparse
import datetime
import hashlib
import json
import os
import sys
from pathlib import Path
from collections import defaultdict

import yaml

ROOT = Path(__file__).resolve().parent.parent

STATUS_ENUM = {"pending", "submitted", "accepted"}
TYPE_ENUM = {"ecological", "project"}
SUPPORT_ENUM = {"maintained", "security-only", "eol"}


def load_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def collect_versions() -> list[dict]:
    out = []
    for kind, sub in (("production", "versions"), ("demo", "demos")):
        base = ROOT / sub
        if not base.exists():
            continue
        for vp in sorted(base.glob("*/version.yaml")):
            m = load_yaml(vp)
            m["_kind"] = kind
            m["_path"] = str(vp.relative_to(ROOT))
            out.append(m)
    return out


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    h.update(p.read_bytes())
    return h.hexdigest()


def _to_iso(v):
    """date/datetime → ISO string;非日期对象原样返回"""
    import datetime as _dt
    if isinstance(v, _dt.datetime):
        return v.isoformat(timespec="seconds")
    if isinstance(v, _dt.date):
        return v.isoformat()
    return v


def build_manifest(versions: list[dict], repo: str, branch: str, commit: str) -> dict:
    """生成 Patch Manifest。规范 §9.2 全部字段。"""
    now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    versions_out = []
    patch_total = 0
    for v in versions:
        vid = v.get("version_id", "")
        support = v.get("support", {}) or {}
        ub = v.get("upstream_base", {}) or {}
        validation = v.get("validation", {}) or {}
        version_block = {
            "version_id": vid,
            "maintained_status": support.get("status", "maintained"),
            "planned_eol": _to_iso(support.get("planned_eol", "")),
            "release_owner": support.get("release_owner", ""),
            "upstream": {
                "repo": ub.get("repo", ""),
                "tag": ub.get("version", ""),
                "commit": ub.get("commit", ""),
            },
            "validation": validation,
            "patches": [],
        }

        for idx, p in enumerate(v.get("patches", []) or [], start=1):
            patch_total += 1
            name = p.get("name", "")
            patch_file = ROOT / v["_path"].replace("version.yaml", "patches") / f"{name}.patch"
            content_sha = sha256_file(patch_file) if patch_file.exists() else ""
            ex = p.get("exception", None)
            if isinstance(ex, dict):
                ex = {k: _to_iso(v) for k, v in ex.items()}
            entry = {
                "sequence": idx,
                "name": name,
                "owner": p.get("owner", ""),
                "type": p.get("type", ""),
                "status": p.get("status", ""),
                "upstream_pr": p.get("pr", ""),
                "test_profile": p.get("test_profile", ""),
                "dependence": p.get("dependence", []),
                "content_sha256": content_sha,
                "exception": ex,
            }
            version_block["patches"].append(entry)

        versions_out.append(version_block)

    return {
        "manifest_version": 1,
        "generated_at": now,
        "generator": "tools/sync-manifest.py",
        "source": {
            "repository": repo,
            "branch": branch,
            "commit": commit,
        },
        "summary": {
            "version_count": len(versions_out),
            "patch_count": patch_total,
        },
        "versions": versions_out,
    }


def validate_versions(versions: list[dict]) -> list[str]:
    """version.yaml 字段校验,符合规范 §4.2 + §4.4"""
    errs = []
    for v in versions:
        path = v.get("_path", "?")
        vid = v.get("version_id", "")
        if not vid:
            errs.append(f"{path}: missing version_id")
        if not v.get("description"):
            errs.append(f"{path}: missing description")
        if not v.get("owner"):
            errs.append(f"{path}: missing owner")

        # support 块
        support = v.get("support", {}) or {}
        if not support:
            errs.append(f"{path}: missing support block (§3.2)")
        else:
            if support.get("status") not in SUPPORT_ENUM:
                errs.append(f"{path}: support.status={support.get('status')!r} not in {sorted(SUPPORT_ENUM)}")
            if not support.get("planned_eol"):
                errs.append(f"{path}: missing support.planned_eol")
            if not support.get("release_owner"):
                errs.append(f"{path}: missing support.release_owner")

        # upstream_base
        ub = v.get("upstream_base", {}) or {}
        if not ub.get("repo"):
            errs.append(f"{path}: missing upstream_base.repo")
        if not ub.get("version"):
            errs.append(f"{path}: missing upstream_base.version")
        commit = ub.get("commit", "")
        if not commit or len(commit) != 40:
            errs.append(f"{path}: upstream_base.commit must be 40-char SHA, got {commit!r}")

        # validation
        val = v.get("validation", {}) or {}
        if not val.get("upstream_commands"):
            errs.append(f"{path}: missing validation.upstream_commands (§4.2 必填)")

        # patches
        patches = v.get("patches", []) or []
        if not patches:
            errs.append(f"{path}: patches[] must be non-empty")
        names = []
        for i, p in enumerate(patches, start=1):
            n = p.get("name", "")
            names.append(n)
            t = p.get("type", "")
            s = p.get("status", "")
            if t not in TYPE_ENUM:
                errs.append(f"{path}: patches[{i}].type={t!r} not in {sorted(TYPE_ENUM)}")
            if s not in STATUS_ENUM:
                errs.append(f"{path}: patches[{i}].status={s!r} not in {sorted(STATUS_ENUM)}")
            if not p.get("owner"):
                errs.append(f"{path}: patches[{i}].owner missing")
            if s == "submitted" and not p.get("pr"):
                errs.append(f"{path}: patches[{i}].status=submitted but pr empty (§4.4)")
            if s == "accepted" and t == "project" and not p.get("exception"):
                errs.append(f"{path}: patches[{i}].type=project status=accepted but exception missing (§4.4)")
            if p.get("exception") and not (p["exception"].get("approved_by") and len(p["exception"]["approved_by"]) >= 2):
                errs.append(f"{path}: patches[{i}].exception.approved_by needs ≥2 distinct roles (§8)")
        if len(names) != len(set(names)):
            errs.append(f"{path}: duplicate patch names in patches[]")

    return errs


def detect_repo_metadata() -> tuple[str, str, str]:
    """从 git 读 repo/branch/commit,符合规范 §3.1"""
    import subprocess
    try:
        repo = subprocess.check_output(
            ["git", "config", "--get", "remote.origin.url"],
            cwd=str(ROOT), text=True, stderr=subprocess.DEVNULL
        ).strip() or "local"
        branch = subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=str(ROOT), text=True, stderr=subprocess.DEVNULL
        ).strip() or "local"
        commit = subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=str(ROOT), text=True, stderr=subprocess.DEVNULL
        ).strip() or "0000000000000000000000000000000000000000"
    except Exception:
        repo, branch, commit = "local", "local", "0" * 40
    return repo, branch, commit


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "out" / "patches-manifest.json"))
    ap.add_argument("--print", action="store_true", help="打印到 stdout,不算写文件")
    args = ap.parse_args()

    versions = collect_versions()
    errs = validate_versions(versions)
    if errs:
        print("=== version.yaml 字段校验失败 ===", file=sys.stderr)
        for e in errs:
            print(f"  ✗ {e}", file=sys.stderr)
        return 2

    repo, branch, commit = detect_repo_metadata()
    manifest = build_manifest(versions, repo, branch, commit)

    if args.print:
        print(json.dumps(manifest, indent=2, ensure_ascii=False))
        return 0

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"✓ wrote {out.relative_to(ROOT)}")
    print(f"  versions={manifest['summary']['version_count']}  patches={manifest['summary']['patch_count']}")
    print(f"  source: {repo} @ {branch} ({commit[:8]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
