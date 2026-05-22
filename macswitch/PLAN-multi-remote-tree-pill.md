# Plano — Suporte Multi-Remote na Pílula da Árvore

## Contexto / Problema

Usuário tem 2 remotes (ex.: `origin` pessoal + `bitbucket`). Interações da pílula da árvore (double-click) hoje atendem só **um** remote — sem dizer qual, sem permitir escolher.

Casos afetados:
1. **Post to remote** (push da pílula) — hardcoded `origin`:
   - `Sources/Zion/Views/Main/ContentView+ContextMenus.swift:178,181,189` → `model.pushBranch(branch, to: "origin", …)`
2. **Create Pull Request** — usa primeiro provider detectado em `remotes` loop:
   - `Sources/Zion/Views/Operations/PullRequestSheet.swift:255,320` → `detectHostingProvider()`
   - `Sources/Zion/ViewModel/RepositoryViewModel+RemoteSync.swift:80-96` → percorre `remotes` na ordem do array, retorna o primeiro GitHub/GitLab/Bitbucket/Azure que casar

Consequência: usuário acha que está abrindo PR no Bitbucket, abre no GitHub pessoal (ou vice-versa). Ruído e risco de vazar branch para o remote errado.

## Objetivo

- Mostrar **qual remote** vai receber a ação antes de confirmar.
- Quando >1 remote existir, **deixar escolher** (com default lembrado).
- Zero fricção quando só 1 remote (comportamento atual).

## Estado Atual — arquivos-chave

| Arquivo | Papel |
|---|---|
| `Sources/Zion/Models/GitModels.swift:102` | `RemoteInfo { name, url }` |
| `Sources/Zion/Models/RepositoryModels.swift:121` | `remotes: [RemoteInfo]` no repo state |
| `Sources/Zion/ViewModel/RepositoryViewModel+GitBranching.swift:49` | `pushBranch(_, to: String, …)` |
| `Sources/Zion/ViewModel/RepositoryViewModel+RemoteSync.swift:80` | `detectHostingProvider()` — retorna 1º match |
| `Sources/Zion/Views/Main/ContentView+ContextMenus.swift:178-189` | Call sites hardcoded `"origin"` |
| `Sources/Zion/Views/Operations/PullRequestSheet.swift:241-330` | PR sheet usa `detectHostingProvider()` |
| `Sources/Zion/Services/{GitHub,GitLab,Bitbucket,AzureDevOps}Client.swift` | `parseRemote(url)` por provider |

## Proposta

### Fase 1 — Infra (ViewModel + persistência)

1. **Preferência de remote default por repo** (lembrar escolha do usuário):
   - Novo campo em `UserDefaults` (chave: `preferredRemote.<repoURL-hash>` → `String?` nome do remote).
   - Helper em `RepositoryViewModel+RemoteSync.swift`:
     - `var preferredRemoteName: String? { get set }`
     - `func resolveTargetRemote(for action: RemoteAction) -> RemoteInfo?` — retorna preferred se existir, senão `origin`, senão primeiro.
   - `enum RemoteAction { case push, createPR }` (permite default diferente por ação no futuro — começar igual).

2. **Generalizar `detectHostingProvider()`**:
   - Adicionar `detectHostingProvider(for remoteName: String)` → resolve provider para 1 remote específico.
   - Manter versão sem parâmetro como fallback (mantém compat).

3. **Listar remotes hospedados**:
   - `func hostedRemotes() -> [(remote: RemoteInfo, provider: any GitHostingProvider, hosted: HostedRemote)]` — todos os remotes com provider detectado. Usado por UI de escolha.

### Fase 2 — UI: Post to remote (push da pílula)

Call sites em `ContentView+ContextMenus.swift:178-189`:

- **1 remote** → push direto, tooltip/label mostra nome (`"Push to origin"` em vez de `"Push"`).
- **2+ remotes** → menu inline no double-click com submenu:
  - `Post to origin` (default marcado)
  - `Post to bitbucket`
  - `Always use [origin/bitbucket]…` (seta preferred).
- Confirmação de push (se já existe) passa a incluir nome do remote no diálogo: `"Push main to bitbucket?"`.

Alternativa mais simples p/ MVP: sempre mostrar picker quando >1 remote, sem default. Acelera POC, refina depois.

### Fase 3 — UI: Create Pull Request

`PullRequestSheet.swift`:

- Topo do sheet: **dropdown de remote** quando `hostedRemotes().count > 1`:
  - Label: `Abrir PR em:` + picker mostrando `origin (GitHub)` / `bitbucket (Bitbucket)`.
  - Seleção persiste em `preferredRemoteName`.
- Quando só 1 hospedado, mostrar badge somente-leitura com nome + ícone do provider (sem picker).
- `detectHostingProvider()` → trocar por `detectHostingProvider(for: selectedRemote)`.
- Validação: se o branch não foi pushed **para o remote escolhido**, erro específico (`branchNotOnRemote:` com nome). Hoje já tem check de push mas é genérico.

### Fase 4 — Indicadores visuais na árvore (opcional, pós-MVP)

- Pílulas/badges de branch mostram ícone do provider do remote default.
- Quando ahead/behind conflita entre remotes, mostrar qual está sendo comparado.

## Testes

1. `preferredRemoteNameTests` — persistência roundtrip.
2. `resolveTargetRemoteTests` — preferred > origin > primeiro; filtra remotes inexistentes.
3. `hostedRemotesTests` — retorna só remotes com provider parseável; preserva ordem.
4. Smoke manual: repo com `origin` (GitHub pessoal) + `bitbucket` (Bitbucket). Double-click pílula → menu com ambos. PR sheet → picker. Usuário abre PR no Bitbucket → verifica que `bitbucketClient.createPullRequest` é chamado.

## Localização (pt-BR, en, es)

Novas chaves:
- `pill.postTo.title` = `"Post to %@"`
- `pill.postTo.menu.always` = `"Always use %@"`
- `pr.remote.picker.label` = `"Open PR on:"`
- `pr.remote.picker.empty` = `"No hosted remote detected"`
- `push.confirm.withRemote` = `"Push %@ to %@?"` (branch, remote)

## Ordem de execução

1. Fase 1 (infra + tests) — branch isolado, PR pequeno.
2. Fase 2 (push UI) — PR #2.
3. Fase 3 (PR sheet picker) — PR #3.
4. Fase 4 (badges visuais) — backlog.

## Risco / Pegadinhas

- **Não quebrar single-remote flow** — comportamento default idêntico quando só há `origin`.
- `detectHostingProvider()` tem vários call sites (AICodeReview, PRReview, RemoteSync:309). Manter overload sem parâmetro para não quebrar; novos usam o com `for:`.
- Preferência é por repo, não global — dois repos podem ter remotes com mesmo nome mas hosts diferentes.
- Azure DevOps tem fluxo próprio (`GitAuthContext.isAzureDevOps`) — validar que picker respeita.

## Perguntas abertas

- Default picker "lembrar sempre" ou perguntar cada push? Proponho **lembrar**, com toggle no menu.
- Mostrar URL completa do remote ou só nome? Proponho **nome + host** (`origin · github.com/nico/foo`).
