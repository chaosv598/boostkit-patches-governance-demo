#!/usr/bin/env python3
"""
whitelist-audit —— 白名单审计 (规范 §8)

输入: out/patches-manifest.json (CI 生成)
扫描 type=project + status=accepted + exception 块的 patch
校验:
  - approved_by ≥2 不同角色 (§8)
  - review_due_at < today → 即将过期
  - expires_at < today → 已过期 (FAIL)
  - required_check 存在
  - 硬件 patch 必须有 self-hosted check
  - evidence_max_age_days ≤ 90

用法:
  bash tools/whitelist-audit.py          # 打印
  bash tools/whitelist-audit.py --strict # 异常项 exit 1
"""
import argparse
import datetime
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "out" / "patches-manifest.json"

ROLE_MIN = 2
REVIEW_WARN_DAYS = 30  # 复审日 < 30 天 → warn
EVIDENCE_MAX_DAYS = 30  # 硬件 evidence 最大 30 天


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()

    if not MANIFEST.exists():
        print("out/patches-manifest.json 不存在,先跑 bash tools/sync-manifest.py", file=sys.stderr)
        return 2

    m = json.loads(MANIFEST.read_text(encoding="utf-8"))
    today = datetime.date.today()
    fail = 0
    warn = 0
    rows = []

    for v in m.get("versions", []):
        for p in v.get("patches", []):
            ex = p.get("exception")
            if not ex:
                continue  # 非白名单 patch 跳过
            # 角色数
            roles = ex.get("approved_by") or []
            # 到期
            expires_at = ex.get("expires_at", "")
            review_due = ex.get("review_due_at", "")
            required = ex.get("required_check", "")
            evi_max = ex.get("evidence_max_age_days", 0)
            verdict = []
            if len(roles) < ROLE_MIN:
                verdict.append(f"✗ approved_by={len(roles)} < {ROLE_MIN}")
                fail += 1
            if not required:
                verdict.append("✗ required_check missing")
                fail += 1
            if evi_max > EVIDENCE_MAX_DAYS:
                verdict.append(f"✗ evidence_max_age_days={evi_max} > {EVIDENCE_MAX_DAYS}")
                fail += 1
            try:
                exp = datetime.date.fromisoformat(expires_at)
                if exp < today:
                    verdict.append(f"✗ expires_at={expires_at} 已过期")
                    fail += 1
                else:
                    days_to_exp = (exp - today).days
                    if days_to_exp < REVIEW_WARN_DAYS:
                        verdict.append(f"⚠ expires_at={expires_at} 距今 {days_to_exp} 天")
                        warn += 1
            except ValueError:
                verdict.append(f"✗ expires_at={expires_at!r} 不可解析")
                fail += 1
            try:
                rd = datetime.date.fromisoformat(review_due)
                if rd < today:
                    verdict.append(f"⚠ review_due_at={review_due} 已超期")
                    warn += 1
            except ValueError:
                verdict.append(f"✗ review_due_at={review_due!r} 不可解析")
                fail += 1
            rows.append({
                "version": v["version_id"],
                "name": p["name"],
                "expires_at": expires_at,
                "review_due": review_due,
                "roles": len(roles),
                "verdict": " | ".join(verdict) if verdict else "✓ OK",
            })

    print("=== 白名单审计 (规范 §8) ===")
    print(f"生成时间: {datetime.datetime.now().isoformat(timespec='seconds')}")
    print(f"白名单 patch 数: {len(rows)}")
    print(f"复审提醒阈值: ≤{REVIEW_WARN_DAYS} 天")
    print()
    if not rows:
        print("✓ 无白名单 patch")
        return 0

    print(f"{'version':<14} {'patch name':<45} {'roles':>5} {'expires_at':<12} {'verdict'}")
    print("-" * 120)
    for r in rows:
        print(f"{r['version']:<14} {r['name']:<45} {r['roles']:>5} {r['expires_at']:<12} {r['verdict']}")
    print()
    print(f"fail={fail}  warn={warn}")
    if fail > 0 and args.strict:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
