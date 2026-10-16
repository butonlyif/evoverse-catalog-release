# EvoVerse Catalog (Customer Release)

English | [中文](release-README.md)

This repository is the versioned design material library of the EvoVerse SDK: it provides the
**hardware physical boundaries** for project generation (the authoritative device pin library, board
pin tables and bank voltage constraints) and **verified reference designs** (stage-0 skeletons, demo
projects, reusable IPs).

The release tree contains only the material assets consumed by the SDK; the development environment
(validation scripts, schemas, tests, CI, migration ledger) stays on the internal development branch
and is not distributed with this library.

## Directory Layout

```text
catalog/
├── catalog.yaml        # version manifest: catalogVersion, releaseTag, treeDigest, item ledger
├── boards/             # board assets (board → carrier → jacket three-layer model)
│   ├── t20f256-xd-ps-eval/   # standalone board: Trion T20F256 (jackets: stage0, marquee)
│   ├── ws-e1/                # module board: Titanium TJ180A484S + carrier ws-e1-base
│   │   └── carriers/ws-e1-base/  # jackets, 10 demos, 9 carrier-level IPs
│   ├── ws-e2/                # module board: RK3588J EVM + FPGA carrier (offline env & baselines)
│   └── ws-e3/                # standalone board: Titanium TJ375N484X (jacket: stage0)
├── devices/            # authoritative device pin library (*.authority.json: per-pin name/bank/voltage_domain/functions/reserved_for)
└── ips/                # globally reusable IPs (protocol bridges, FIFOs, reset sync, video timing/patterns, with RTL and docs)
```

Most documents ship in two languages side by side: `X.md` is the Chinese original and `X.en.md` is
the English sibling; the top of each file links to the other.

## Board Hierarchy Model

- **board**: the authoritative definition of a physical board, including its pin table (pinout) and
  bank voltage constraints.
- **carrier**: the expansion baseboard that a module board (e.g. ws-e1, ws-e2) plugs into,
  completing the pin mapping for expansion peripherals; standalone boards have no such layer.
- **jacket**: a concrete design deliverable layered on top of a board or carrier (RTL, constraints,
  project description).
- **demo**: a complete demonstration project attached under a carrier, targeting a specific hardware
  scenario.

When the SDK generates a project, `devices/*.authority.json` and the board pinout act as the
physical boundary: any pin assignment outside the authoritative library, voltage-domain conflict or
reserved-pin occupation is rejected.

## Fetch and Verify

```bash
git fetch origin tag catalog-v0.9.6
git checkout catalog-v0.9.6
```

The `treeDigest` in `catalog.yaml` is a SHA-256 content fingerprint over all material content
(boards/, devices/, ips/). The EvoVerse SDK verifies this fingerprint automatically during catalog
sync; any tampering or omission causes the sync to fail. For manual verification, use the catalog
validator bundled with the SDK.

## Version Contract

- `catalogVersion`: the material library version, one-to-one with the release tag
  `catalog-v<catalogVersion>`.
- `minimumSdkVersion`: the minimum SDK version required to consume this library.
- `channel`: `stable` (verified) or `preview`.

## License

The contents of this library are licensed under `LicenseRef-EvoVerse-Catalog` and may only be used
by EvoVerse-authorized customers within EvoVerse SDK workflows.
