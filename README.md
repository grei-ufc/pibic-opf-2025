# pibic-opf-2025 — Fluxo de Potência com Ações de Controle ANAREDE em JuMP/Julia

Projeto de iniciação científica (PIBIC) e Trabalho de Conclusão de Curso em
Engenharia Elétrica (UFC), de **Gabriel Rufino Montenegro**, orientado pelo
**Prof. Lucas Silveira Melo**.

O trabalho constrói, valida e compara uma **progressão incremental de
formulações de Fluxo de Potência (FP) e Fluxo de Potência Ótimo (FPO) AC** em
JuMP/Julia sobre o solver Ipopt, incorporando uma a uma as **ações de controle
do programa ANAREDE** (CEPEL): QLIM, VLIM, CSCA, CTAP e um esquema hierárquico
de corte de carga (rotulado DERA). As formulações são comparadas contra as duas
referências do *PowerModels.jl* (`solve_ac_opf` e `solve_ac_pf`) sobre uma
bateria de 27 casos ANAREDE (`.pwf`), de redes de 3 barras até um *snapshot*
integral do SIN com 13.338 barras.

**Ideia central:** em vez dos laços iterativos e chaveamentos discretos do
ANAREDE, cada controle entra no modelo como *soft-constraint* — variáveis de
folga penalizadas na função objetivo. Quando o problema é factível respeitando
os *setpoints*, as folgas zeram; quando não é, o solver encontra o ponto que
**viola minimamente** os controles, em vez de declarar `INFEASIBLE`.

## Instalação

Ver **[INSTALACAO.md](INSTALACAO.md)** — inclui o `setup.jl`, que reproduz o
ambiente com as versões exatas dos pacotes (Julia 1.8.3, JuMP 0.22.3,
PowerModels 0.19.10, Ipopt 0.9.1, PWF.jl em commit pinado).

```bash
juliaup add 1.8.3
julia +1.8.3 setup.jl
```

> ⚠️ Não rode `Pkg.update()`: o código usa a API antiga do JuMP (0.22,
> `@NLexpression`/`@NLconstraint`) e quebra com JuMP ≥ 1.0.

## Como rodar

Cada formulação é um script auto-contido. O caso `.pwf` é escolhido na linha
`arquivo = ...` (ou `caminho_arquivo = ...`) no fim de cada script:

```bash
# da raiz do repositório
julia --project=. "powerflow/Codes/PF_Formulation/(F2)QLIM+VLIM.jl"
```

As saídas são dois CSVs em `powerflow/Codes/PF_Formulation/resultados_csv/`
(`resultados_barras_SIN.csv` e `resultados_fluxos_linhas_SIN.csv`), em p.u.,
ângulos em radianos, **sobrescritos a cada execução** — copie antes de comparar.

## A progressão de formulações

Os scripts em `powerflow/Codes/PF_Formulation/` não são alternativas paralelas:
formam uma progressão **estritamente aditiva** — cada arquivo parte do anterior
e acrescenta um único bloco de variáveis/restrições, de modo que qualquer
divergência entre dois scripts consecutivos é atribuível ao novo controle.

| Sigla | Arquivo | Motor | Acrescenta |
|---|---|---|---|
| F0 | `(F0)OPF_PM.jl` | PowerModels `solve_ac_opf` | *baseline* FPO AC |
| F1 | `(F1)PF_PM.jl` | PowerModels `solve_ac_pf` | *baseline* FP AC (sem otimização) |
| F2 | `(F2)QLIM+VLIM.jl` | JuMP *hand-built* | folgas de tensão (VLIM) e reativo (QLIM), penalidade ρ=10⁶ |
| F3 | `(F3)QLIM+VLIM+CSCA.jl` | JuMP | + susceptância *shunt* chaveável como variável contínua (CSCA) |
| F4 | `(F4)QLIM+VLIM+CSCA+CTAP.jl` | JuMP | + *tap* de transformador OLTC como variável contínua (CTAP) |
| F5 | `(F5)+DERA.jl` | JuMP | + corte hierárquico de carga ponderado por tensão-base (DERA) |
| FDC | `(FDC).jl` | PowerModels `solve_dc_pf` | verificação auxiliar: aproximação DC do caso SIN (`max_iter=20000`) |

Convenções importantes:

- **Leitura PWF:** `PWF.parse_file(path; add_control_data = true)` — o flag é
  obrigatório para expor os metadados de controle (DOPC/DLIN).
- **HVDC:** injeções fixadas via `JuMP.fix(...; force=true)` (condição de
  contorno do FP AC); retificador com `pg` negativo, inversor positivo.
- **Múltiplas barras de referência:** os scripts rebaixam as excedentes para PV
  e mantêm uma única *slack* — necessário no caso SIN, não remover.
- **Ipopt permissivo:** `max_iter=3000`, `tol=1e-5` — o caso SIN é rígido; não
  apertar sem re-testar.

## Estrutura do repositório

```
├── Project.toml / Manifest.toml     # ambiente Julia pinado (raiz do repo)
├── setup.jl / INSTALACAO.md         # instalação reproduzível em máquina nova
├── powerflow/
│   ├── Codes/
│   │   ├── PF_Formulation/          # ★ código ativo: progressão F0–F5 + FDC
│   │   │   ├── runner/              # bateria automatizada (ver abaixo)
│   │   │   ├── resultados_csv/      # saídas por formulação/caso + consolidados
│   │   │   ├── Desenvolvimento/     # rascunhos históricos (3)–(13); não estender
│   │   │   └── 0-Trash/             # descartes
│   │   ├── data/                    # 27+ casos ANAREDE .pwf (ver abaixo)
│   │   ├── PowerModels/             # CodeComparing.jl: AC vs DC vs SOC no case5.m
│   │   └── New_ControlPF (Prof-Lucas)/  # cópia local do ControlPowerFlow.jl
│   │                                #   (referência do orientador; só leitura)
│   └── Arquivos-CSV/                # resultados antigos de estudos PowerModels
├── Modelo_de_Trabalho_Acadêmico_UFC/  # ★ TCC em LaTeX (documento.pdf)
├── Template_Beamer_UFC/             # ★ apresentação da defesa (document.pdf)
│   └── roteiro_falas.tex/.pdf       #   roteiro de falas pareado com os slides
├── Learning_Period/                 # material de estudo do período inicial
├── short-reports/                   # relatórios curtos periódicos ao orientador
├── _batch_isabela.sh                # batch de validação dos casos caso_red/red2
└── _comparacao_red/                 # CSVs de comparação dos casos reduzidos
```

### Casos de teste (`powerflow/Codes/data/`)

- **Pedagógicos:** `3bus` e variantes por seção PWF (`_DBSH`, `_DCER`, `_DCSC`,
  `_DSHL`, `_DCline`, ...), família *frank* (`3busfrank`, `4busfrank_vlim`,
  `5busfrank_csca/_ctap/_ctaf/_cphs`), `9bus` (Anderson-Fouad).
- **Médio porte:** `300bus.pwf` (IEEE 300), `500bus.pwf` (sintética).
- **SIN integral:** `CASO_VER_MAXDIU.PWF` — Verão 2027/2028 Máxima Diurna,
  PAR/PEL 2027-2031 do ONS, 13.338 barras (caso usado no TCC). Há também
  `01 MAXIMA NOTURNA_DEZ25.PWF` (12.618 barras) e outros *snapshots* DEZ25,
  usados nas fases anteriores do projeto.
- **Recortes reduzidos do SIN** (colaboração M.Sc. Isabela Metzker/ONS,
  derivados do `CASO_VER_MAXDIU`): `caso_red.pwf` (Nordeste completo, 2.599
  barras, 15 barras de fronteira no eixo PI-BA) e `caso_red2.pwf` (CE+RN+PB,
  1.033 barras). Fronteira híbrida: cargas equivalentes no DBAR + ramos
  equivalentes no DLIN (as "perdas" incluem a dissipação desses equivalentes).
- **Stress de parser:** `test_defaults`, `test_line_shunt`, `test_system`,
  `3bus_corrections` (dispara erro de parser propositalmente).

### A bateria automatizada (`runner/`)

Os scripts do `runner/` executam as seis formulações sobre todos os casos e
consolidam os resultados. **Atenção à numeração:** o runner e as pastas de
resultados usam a numeração **antiga** dos scripts — o mapeamento é:

| Antiga (runner, `resultados_csv/<n>/`) | 14 | 15 | 16 | 17 | 18 | 19 |
|---|---|---|---|---|---|---|
| **Nova (TCC, arquivos `(Fx)`)** | F0 | F1 | F2 | F3 | F4 | F5 |

- `runner_analise_tcc.jl` — roda a bateria completa (um subprocesso por par
  caso×formulação, com *timeout*);
- `rerun_sin.jl` — re-roda apenas o caso SIN sem *wall-clock timeout*;
- `consolidar.jl` / `_consolidate_masters.jl` — agregam os CSVs por caso em
  `resultados_csv/convergencia.csv`, `clusters.csv`, `barras.csv`, `ramos.csv`;
- `gerar_relatorio.jl` — produz o relatório de convergência/divergência
  barra-a-barra de que saem as tabelas do capítulo de Resultados do TCC.

Critérios usados na análise (detalhes no cap. 3 do TCC): status de convergência
em 8 categorias (OK/INF/ITL/TIM/KIL/CRA/INV/ERR); *clusters* de equivalência
numérica com tolerância 10⁻⁴ em V, θ, pg, qg e fluxos; análise barra-a-barra
contra as referências F0/F1.

## Documentos

- **TCC:** `Modelo_de_Trabalho_Acadêmico_UFC/documento.pdf` (fonte em
  `2-textuais/*.tex`; compilar com o `Makefile` da pasta). Título: *"Análise
  comparativa de formulações de Fluxo de Potência Ótimo com ações de controle
  em JuMP/Julia"* (2026).
- **Apresentação da defesa:** `Template_Beamer_UFC/document.pdf`, com roteiro
  de falas em `roteiro_falas.pdf`.

## Para quem for continuar o desenvolvimento

Frentes abertas (cap. 5 do TCC):

1. **Convergência do SIN integral** — nenhuma formulação AC converge no
   `CASO_VER_MAXDIU` (a FDC, em DC, converge, mostrando que o obstáculo é
   numérico e não estrutural). Caminhos: verificação de resíduos alimentando o
   modelo com a solução do PWF; auditoria da tradução PWF→JuMP (HVDC,
   intercâmbios, controles remotos, múltiplas referências); homotopia nas
   penalidades ρ; opções de robustez do Ipopt. **Nota:** os scripts já
   inicializam do ponto convergido do ANAREDE lido do PWF — *warm-start* pela
   solução DC **não** ajuda (ângulos de ±170° a violam as hipóteses DC).
2. **Discretização de CSCA/CTAP** — hoje contínuos; transformar F3/F4 em MINLP
   (Juniper, Alpine, SCIP).
3. **Acoplamento ao ControlPowerFlow.jl** — usar F2–F5 como *oracle* de
   validação do pacote do grupo do orientador (cópia de referência em
   `New_ControlPF (Prof-Lucas)/` — não refatorar, é código de upstream).

Regras práticas ao mexer no código:

- Para adicionar um novo controle, copie a formulação anterior e acrescente
  apenas o novo bloco (mantendo a progressão aditiva).
- "Verificar uma mudança" = re-rodar a formulação afetada num caso pequeno
  (`3bus.pwf`/`9bus.pwf`) e comparar os CSVs com o *baseline* F0/F1 no mesmo
  caso (copie os CSVs antes, pois são sobrescritos).
- Código, comentários e docs em **português (pt-BR)**.

## Licença

Ver [LICENSE](LICENSE).
