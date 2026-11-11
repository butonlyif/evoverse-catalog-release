# Board Catalog layout

The board catalog uses one canonical identifier for the directory, manifest,
CLI, IDE, and project manifest.

## Module board

```text
boards/<board-id>/
├── <board-id>.md
├── docs/
└── carriers/<carrier-id>/
    ├── <carrier-id>.md
    ├── docs/
    ├── pinout/<carrier-id>.csv
    ├── constraints/
    │   ├── <carrier-id>.interface.isf
    │   ├── <carrier-id>.pins.isf
    │   └── <carrier-id>.sdc
    ├── generated/
    ├── demo/
    └── jackets/<jacket-id>/
        └── <jacket-id>.md
```

A module has no root `constraints/`. Project creation must select a carrier,
and that carrier supplies a self-contained Efinity constraint set.

## Standalone board

A standalone board uses the same `docs/`, `pinout/`, `constraints/`,
`generated/`, `demo/`, and `jackets/` directories directly below its board
directory. It does not have `carriers/`.

## Constraint ownership

- `*.interface.isf` contains Interface Designer configuration and electrical
  properties.
- `*.pins.isf` contains final package-pin assignments.
- `*.sdc` contains design timing constraints.
- CSV is documentation or a basic GUI import aid; it is not authoritative.
- `.peri.xml`, `.pt.sdc`, `.pinout.csv`, template Verilog, and reports are
  Efinity outputs and belong in `generated/`.

The SDK copies native ISF/SDC sources unchanged and invokes Efinity
`efx_run_pt_unified.py --peri_scripts`. It does not translate CSV, merge ISF,
infer package balls, or generate Efinity constraint semantics.
