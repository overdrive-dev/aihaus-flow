# aihaus Roles (capability profiles)

> Modelo de roles do aihaus 3.0. Roles são **capacidades aditivas**, não personas
> exclusivas — um profile pode ter vários ao mesmo tempo (ex. `builder,devops`).
> O profile ativo é declarado em `.aihaus/.profile` (separado por vírgula/espaço).
>
> NOTA: estes roles de PRODUTO (builder/dev/qa/devops/pm) são distintos dos roles de
> COHORT de agente (`:planner`/`:doer`/...) usados pelo context-inject
> (`hooks/lib/role-defaults.json`). Não confundir.

## O boundary de capacidade: "online"

O único boundary de capacidade é se a ação **toca um ambiente online** (staging/
homolog/prod). Tudo offline-local (Docker, dev local) é aberto a builder/dev/qa.
Só um role **online-capable** cruza.

| Role | Direito de mover (estágios) | Online-capable? |
|---|---|---|
| `pm` | backlog → **entendimento** → planejamento | não |
| `builder` | backlog → entendimento → planejamento → desenvolvimento → testes | não |
| `dev` | entendimento → desenvolvimento → testes | não |
| `qa` | backlog → entendimento → planejamento → desenvolvimento → testes (dono: testes/Playwright) | não |
| `devops` | homolog, prod (online) | **sim** |

- **builder** = a persona client-as-builder: guiado na captação de regras de negócio,
  builda features em Docker local, **não** sobe online.
- **pm** participa principalmente do **entendimento** (e backlog/planejamento) — é onde o
  produto garante que o problema/feature está 100% claro antes de especificar (BR-1).
- **qa** tem acesso offline **parecido com o builder** (entendimento → ... → testes), com
  ownership de `testes` e da validação Playwright.
- Um profile é a *união* dos direitos dos seus roles. `builder,devops` builda local
  E cruza o boundary online.

## Enforcement

- **Fase 1 (vs agente autônomo):** `role-guard.sh` (PreToolUse) bloqueia ações que
  tocam ambiente online quando o profile ativo não tem role online-capable. Default
  online-capable: `devops`. Padrões de ação-online: defaults no `role-guard.sh` +
  extensões de projeto em `.aihaus/roles/online-actions.conf` (preenchido pelo
  env-detection do aih-init, fatia S2).
- **Fase 2 (vs humano):** usuário de SO separado + managed-settings + credenciais de
  deploy ausentes do ambiente non-devops (autenticação server-side).

## Sentinel `.aihaus/.profile`

Linha única, roles separados por vírgula/espaço. Exemplos:

```
builder
builder,dev
devops
```

Ausente → role-guard fora de escopo (exit 0); o install se comporta como não-roleado.

Opt-out: `AIHAUS_ROLE_GUARD=0`. Audit: `.claude/audit/role-guard.jsonl`.
