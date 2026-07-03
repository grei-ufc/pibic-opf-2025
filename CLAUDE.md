# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

PIBIC undergraduate-research project on **Optimal Power Flow (OPF)** in Julia, advised by Prof. Lucas. The active research code is in `powerflow/Codes/PF_Formulation/`. The repo is not a package — there is no `src/`, no test suite, no CI; it is a collection of runnable scripts plus inputs and CSV results. The written deliverables live alongside the code: the TCC (LaTeX) in `Modelo_de_Trabalho_Acadêmico_UFC/` and the defense slides in `Template_Beamer_UFC/`.

Most identifiers, file names, comments, and committed docs are in **Portuguese (pt-BR)**. Match that language when editing code/docs unless asked otherwise.

## Running things

The Julia environment lives at the repo root (`Project.toml` / `Manifest.toml`). Always activate it:

```bash
# From the repo root — run any single formulation directly
julia --project=. "powerflow/Codes/PF_Formulation/(F4)QLIM+VLIM+CSCA+CTAP.jl"
```

Or from a REPL: `julia --project=.`, then `include("powerflow/Codes/PF_Formulation/<script>.jl")`.

Environment setup on a fresh machine is scripted: `julia setup.jl` (see `INSTALACAO.md`). Note that `PWF` is a local `develop` dependency (`~/.julia/dev/PWF`, pinned commit + compat patch) — plain `Pkg.instantiate()` fails without it. **Never `Pkg.update()`**: the code targets JuMP 0.22 / Ipopt 0.9 API (`@NLexpression`/`@NLconstraint`).

Each formulation script in `PF_Formulation/` is **self-contained**: it picks one hardcoded `.pwf` case at the bottom (`arquivo = ...` or `caminho_arquivo = ...`) and runs end-to-end. To test against a different `.pwf`, edit that line. For batch runs there is `PF_Formulation/runner/` (see below).

There is no test suite. "Verifying a change" means re-running the affected formulation against a small case (e.g. `3bus.pwf` or `9bus.pwf`), then comparing the resulting CSVs in `resultados_csv/` against either the previous run or the F0/F1 PowerModels baseline on the same case. **Note**: the output CSVs are overwritten on each run — copy or rename them before re-running if you need a before/after diff.

## Architecture: the formulation progression

The `(Fx)` files in `PF_Formulation/` are not parallel alternatives — they are an **incremental progression**, each adding one control action on top of the previous. Read them in order when orienting:

| File | Engine | Adds |
|---|---|---|
| `(F0)OPF_PM.jl` | `PowerModels.solve_ac_opf` | Baseline AC OPF reference |
| `(F1)PF_PM.jl` | `PowerModels.solve_ac_pf` | Plain AC power flow (no optimization) — baseline for the controlled formulations |
| `(F2)QLIM+VLIM.jl` | hand-built JuMP model | Generator Q-limits + bus V-magnitude constraints, enforced via penalty slacks (ρ=1e6) |
| `(F3)QLIM+VLIM+CSCA.jl` | JuMP | + **CSCA**: switchable shunt-susceptance control (banks become continuous decision variables) |
| `(F4)QLIM+VLIM+CSCA+CTAP.jl` | JuMP | + **CTAP**: on-load transformer tap control (tap ratio becomes a continuous decision variable) |
| `(F5)+DERA.jl` | JuMP | + **DERA**: hierarchical load-shedding scheme, linear cost weighted by bus base-voltage (ρ drops to 1e5) |
| `(FDC).jl` | `PowerModels.solve_dc_pf` | Auxiliary DC power flow check on the SIN case (`max_iter=20000`); diagnostic only, outside the F0–F5 progression |

**Numbering legacy:** the batch runner and `resultados_csv/<n>/` folders still use the old script numbers — the mapping is 14→F0, 15→F1, 16→F2, 17→F3, 18→F4, 19→F5.

`runner/` automates the 27-case battery: `runner_analise_tcc.jl` (full battery, one subprocess per case×formulation with timeout), `rerun_sin.jl` (SIN case only, no wall-clock timeout), `consolidar.jl`/`_consolidate_masters.jl` (aggregate into `resultados_csv/convergencia.csv`, `clusters.csv`, `barras.csv`, `ramos.csv`), `gerar_relatorio.jl` (the report the TCC results chapter is built from).

`Desenvolvimento/` holds older numbered drafts ((3)–(13)) that the current progression builds on — read for history, don't extend them. `0-Trash/` is what it sounds like.

The control actions (QLIM, VLIM, CSCA, CTAP, DERA) mirror ANAREDE conventions and are conceptually equivalent to what `ControlPowerFlow.jl` does — these JuMP scripts are the hand-written counterparts used to study/compare against that package.

When adding a new control feature, follow the same incremental pattern: copy the previous formulation file, add the new variables/constraints/objective penalties to it.

A separate side study lives at `powerflow/Codes/PowerModels/CodeComparing.jl` — it solves the stock `case5.m` (from PowerModels' test data) under AC, DC, and SOC relaxations to compare objective bounds. It is unrelated to the F0–F5 progression and operates on a fixed Matpower case rather than `.pwf` input.

## Inputs and outputs

- **Inputs:** ANAREDE `.pwf` files in `powerflow/Codes/data/` (3bus + variants, frank family, 9bus, 300bus, 500bus, SIN snapshots). Parsed with `PWF.parse_file(path; add_control_data = true)` — the `add_control_data` flag is required to surface CSCA/CTAP/QLIM/VLIM metadata from `DOPC`/`DLIN` sections. The main SIN case for the TCC is `CASO_VER_MAXDIU.PWF` (13,338 buses, PAR/PEL 2027-2031); `01 MAXIMA NOTURNA_DEZ25.PWF` (12,618 buses) is the earlier snapshot the batch runner/consolidated CSVs were built on. Script defaults are mixed (F1/F4/FDC point at CASO_VER_MAXDIU; F2/F3/F5 at 01 MAXIMA NOTURNA) — always check the bottom-of-file `arquivo = ...` line. `caso_red.pwf` (2,599 buses) / `caso_red2.pwf` (1,033 buses) are Nordeste cuts of CASO_VER_MAXDIU with hybrid-boundary equivalents.
- **Outputs:** every formulation writes the same two filenames into `powerflow/Codes/PF_Formulation/resultados_csv/`: `resultados_barras_SIN.csv` (per-bus: Vm/Va/Pg/Qg/Pload/Qload + slacks) and `resultados_fluxos_linhas_SIN.csv` (per-line: both-direction P/Q + losses + tap). **These get overwritten on every run** — there is no per-case or per-formulation suffix. Copy or rename them before re-running if you need to compare. The runner is the exception: it archives per-case copies under `resultados_csv/<n>/<caso>/`.

## `New_ControlPF (Prof-Lucas)/`

Local vendored copy of an in-development `ControlPowerFlow.jl` from Prof. Lucas (not a submodule, not the registered package). Treat it as upstream-owned reference code — don't refactor it; only read it to understand the package-side implementation of the same control actions the JuMP scripts implement by hand.

## Conventions worth knowing

- Per-unit: results CSVs are in p.u. (column suffix `_pu`); angles in radians.
- The reference for "did the controlled formulation converge sensibly?" is the F0/F1 PowerModels baseline on the same case.
- HVDC links: DC line flows are **fixed** with `JuMP.fix(...; force=true)` rather than left as free variables (see the `notes` text file in `PF_Formulation/`) — the active injections come pre-specified from the base flow, so freeing them just bloats the Jacobian. The rectifier-side dummy gen takes negative `pg`, the inverter-side takes positive `pg`.
- Multiple reference buses: `(F4)` and friends auto-demote extras to PV (type 2) and keep only the first as slack (type 3) after `PWF.parse_file`. This is intentional for the SIN case and shouldn't be removed.
- Ipopt is configured permissively (`max_iter=3000`, `tol=1e-5`) because the SIN-scale cases are stiff. Don't tighten without re-checking the SIN snapshots.
- All formulations initialize V/θ/pg/qg from the ANAREDE converged point read from the PWF (not flat start). The TCC's position (do not contradict it in docs/slides): the SIN convergence obstacle is model fidelity + conditioning, not initialization, and the DC solution is **not** a useful warm start.
