# Kunpeng BoostKit Redis

> Patch overlay governance. Design: [docs/governance.md](./docs/governance.md), schema: [docs/schemas.md](./docs/schemas.md).

Kunpeng BoostKit Redis layers ARM/Kunpeng optimization patches on top of a fixed upstream Redis version. v6.0 aligns with Buildroot `package/<name>/` layout — one version directory, one `manifest.yaml`, feature dirs as siblings.

## Quick Start

```bash
# Full verification (root hygiene + manifest.yaml schema + clean apply)
bash tools/verify.sh

# Patch header lint (DEP-3 6 required + conditional)
python3 .github/lint.py headers versions/*/

# Manifest lint (depends + directory consistency + orphan detection)
python3 .github/lint.py manifest versions/*/

# Or both at once
python3 .github/lint.py all versions/*/
```

**Feature combos**: pick subsets via `ACTIVE_FEATURES`, `apply_patch.sh --manifest` auto-resolves dependencies:

```bash
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --manifest versions/redis-7.0.15/manifest.yaml \
    versions/redis-7.0.15 \
    /tmp/build

# Subset
ACTIVE_FEATURES="rdb-aof-fallback" bash tools/apply_patch.sh ... --manifest ... /tmp/build-a
```

## Design

See:
- **[docs/governance.md](./docs/governance.md)** — design rationale + industry references + workflows + FAQ
- **[docs/schemas.md](./docs/schemas.md)** — authoritative YAML/header field definitions + validation matrix
- **Product guides** — `docs/zh/` (Chinese) / `docs/en/` (English)
- **[docs/research/openEuler-patch-mgmt.md](./docs/research/openEuler-patch-mgmt.md)** — openEuler research

## Contributing

PR-only:

1. Add patch → place under feature directory + write DEP-3 header (6 required)
2. Run local tools green (`verify.sh` + `lint.py headers` + `lint.py manifest`)
3. Open PR → `ci.yml` (3 steps)
4. Review → merge

## License

- Overlay: Apache 2.0 ([LICENSE.txt](./LICENSE.txt))
- Upstream Redis: BSD-3-Clause (preserved in patch headers)
- Product docs: CC-BY 4.0 ([docs/LICENSE](./docs/LICENSE))
