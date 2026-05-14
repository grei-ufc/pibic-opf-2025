# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

PIBIC undergraduate-research project on **Optimal Power Flow (OPF)** in Julia, advised by Prof. Lucas. The active research code is in `powerflow/Codes/PF_Formulation/`. The repo is not a package — there is no `src/`, no test suite, no CI; it is a collection of runnable scripts plus inputs and CSV results.

Most identifiers, file names, comments, and committed docs are in **Portuguese (pt-BR)**. Match that language when editing code/docs unless asked otherwise.

## Running things

The Julia environment lives at the repo root (`Project.toml` / `Manifest.toml`). Always activate it:

```bash
# From the repo root — run any single formulation directly
julia --project=. "powerflow/Codes/PF_Formulation/(18)QLIM+VLIM+CSCA+CTAP.jl"
```

Or from a REPL: `julia --project=.`, then `include("powerflow/Codes/PF_Formulation/<script>.jl")`.

Each formulation script in `powerflow/Codes/PF_Formulation/` is **self-contained**: it picks one hardcoded `.pwf` case at the bottom (`arquivo = joinpath(@__DIR__, "..", "data", "...")`) and runs end-to-end. There is no top-level runner that drives multiple formulations over multiple cases — to test against a different `.pwf`, edit that `arquivo = ...` line (or the `include` path) in the script you're running.

There is no test suite. "Verifying a change" means re-running the affected formulation against a small case (e.g. `3bus.pwf` or `9bus.pwf`), then comparing the resulting CSVs in `resultados_csv/` against either the previous run or the (14)/(15) PowerModels baseline on the same case. **Note**: the output CSVs are overwritten on each run (see "Inputs and outputs" below) — if you need a before/after diff, copy or rename them before re-running.

## Architecture: the formulation progression

The numbered files in `PF_Formulation/` are not parallel alternatives — they are an **incremental progression**, each adding one control action on top of the previous. Read them in order when orienting:

| File | Engine | Adds |
|---|---|---|
| `(14)OPF_PM.jl` | `PowerModels.solve_ac_opf` | Baseline AC OPF reference |
| `(15)PF_PM.jl.jl` | `PowerModels.solve_ac_pf` | Plain AC power flow (no optimization) — baseline for comparing the controlled formulations. The double `.jl.jl` in the filename is intentional, do not "fix" it without checking includes. |
| `(16)QLIM+VLIM.jl` | hand-built JuMP model | Generator Q-limits + bus V-magnitude constraints, enforced via penalty slacks |
| `(17)QLIM+VLIM+CSCA.jl` | JuMP | + **CSCA**: switchable shunt-susceptance control (capacitor/reactor banks become decision variables) |
| `(18)QLIM+VLIM+CSCA+CTAP.jl` | JuMP | + **CTAP**: on-load transformer tap control (tap ratio becomes a continuous decision variable with setpoint slack) |
| `(19)+DERA.jl` | JuMP | + **DERA**: distributed energy resource aggregation on top of (18) |

`Desenvolvimento/` holds older numbered drafts ((3), (11), (12), (13)) that the current progression builds on — read for history, don't extend them. `0-Trash/` is what it sounds like.

The control actions (QLIM, VLIM, CSCA, CTAP, DERA) mirror ANAREDE conventions and are conceptually equivalent to what `ControlPowerFlow.jl` does — these JuMP scripts are the hand-written counterparts used to study/compare against that package.

When adding a new control feature, follow the same incremental pattern: copy the previous-numbered file, add the new variables/constraints/objective penalties to it.

A separate side study lives at `powerflow/Codes/PowerModels/CodeComparing.jl` — it solves the stock `case5.m` (from PowerModels' test data) under AC, DC, and SOC relaxations to compare objective bounds. It is unrelated to the (14)–(19) progression and operates on a fixed Matpower case rather than `.pwf` input.

## Inputs and outputs

- **Inputs:** ANAREDE `.pwf` files in `powerflow/Codes/data/` (3bus + variants, 9bus, 300bus, 500bus, plus `01 MAXIMA NOTURNA_DEZ25.PWF`). Parsed with `PWF.parse_file(path; add_control_data = true)` — the `add_control_data` flag is required to surface CSCA/CTAP/QLIM/VLIM metadata from `DOPC`/`DLIN` sections. The (17)/(18)/(19) scripts default to `01 MAXIMA NOTURNA_DEZ25.PWF` (Brazilian SIN snapshot); the bottom-of-file `arquivo = ...` line is the knob to change.
- **Outputs:** every formulation writes the same two filenames into `powerflow/Codes/PF_Formulation/resultados_csv/`: `resultados_barras_SIN.csv` (per-bus: Vm/Va/Pg/Qg/Pload/Qload + slacks) and `resultados_fluxos_linhas_SIN.csv` (per-line: both-direction P/Q + losses + tap). **These get overwritten on every run** — there is no per-case or per-formulation suffix. Copy or rename them before re-running if you need to compare.

## `New_ControlPF (Prof-Lucas)/`

Local vendored copy of an in-development `ControlPowerFlow.jl` from Prof. Lucas (not a submodule, not the registered package). Treat it as upstream-owned reference code — don't refactor it; only read it to understand the package-side implementation of the same control actions the JuMP scripts implement by hand.

## Conventions worth knowing

- Per-unit: results CSVs are in p.u. (column suffix `_pu`); angles in radians.
- The reference for "did the controlled formulation converge sensibly?" is the (14)/(15) PowerModels baseline on the same case.
- HVDC links: in PowerModels-based scripts, DC line flows are **fixed** with `JuMP.fix(...; force=true)` rather than left as free variables (see the `notes` text file in `PF_Formulation/`) — the active injections come pre-specified from the base flow, so freeing them just bloats the Jacobian. The retifier-side dummy gen takes negative `pg`, the inverter-side takes positive `pg`.
- Multiple reference buses: `(18)` and friends auto-demote extras to PV (type 2) and keep only the first as slack (type 3) after `PWF.parse_file`. This is intentional for the SIN case and shouldn't be removed.
- Ipopt is configured permissively (`max_iter=3000`, `tol=1e-5`) because the SIN-scale case is stiff. Don't tighten without checking it still converges on `01 MAXIMA NOTURNA_DEZ25.PWF`.
