# VS Code Git Extension — Patterns Aplicáveis ao Zion

Fonte: `~/Downloads/vscode-main/extensions/git/src/` (repository.ts, operation.ts, decorators.ts, autofetch.ts, watch.ts, model.ts, git.ts)

## TL;DR — 8 padrões que Zion pode absorver

### 1. Triade de decorators (decorators.ts)
VS Code tem 4 primitivas reutilizáveis aplicadas com `@annotation`:
- `@throttle` — se já rodando, enfileira UMA próxima chamada (não N). Drop de duplicatas em bursts.
- `@debounce(ms)` — timer reseta a cada chamada.
- `@sequentialize` — cada chamada espera a anterior (FIFO).
- `@memoize` — valor computado 1x, vira property.

**Zion hoje:** `runGitAction` é choke point mas não tem esses primitives. Adicionar equivalentes Swift via property wrappers ou helpers em `GitClient` removeria boilerplate e padronizaria proteções em `refresh`, `status`, `fastForward`, `sync`.

### 2. `eventuallyUpdateWhenIdleAndWait` (repository.ts:3186-3213)
```
@debounce(1000) eventuallyUpdateWhenIdleAndWait()
@throttle updateWhenIdleAndWait():
  await whenIdleAndFocused()   // bloqueia se ops rodando OU janela sem foco
  await status()
  await timeout(5000)          // cooldown antes da próxima
```
Nunca refresca com app desfocado; nunca refresca concorrente com outra op git.

**Zion hoje:** `details.reload silent origin=fileWatcher` dispara independente de foco. Mesmo padrão reduziria thrash quando user tá em outro app.

### 3. Watcher apenas em `.git/` com filtro regex (repository.ts:465)
```
watch(repository.dotGit.path)
filter: uri => !/\/\.git(\/index\.lock|\/worktrees\/[^/]+\/index\.lock)?$|\/\.watchman-cookie-/.test(uri.path)
```
Ignora `index.lock` (ruído durante ops), cookie do watchman. `transientDisposables` para upstream refs — desmonta/remonta só quando upstream muda.

**Zion hoje:** se watcher monitora workspace inteiro, `index.lock` flicker causa falsos refreshes. Vale checar `FileWatcher` atual.

### 4. Operation queue tipada (operation.ts)
Toda chamada git é `OperationKind` com flags `{ blocking, readOnly, remote, retry, showProgress }`. `OperationManager` expõe `isIdle()`, `isRunning(kind)`, `shouldShowProgress()`.

Usa para: disable input box durante Commit, gate de idle wait, decisão de mostrar spinner.

**Zion hoje:** `runGitAction` tem label mas não flags. Sem `isRunning(.commit)` → não há como editor saber "commit em voo, desabilita botão".

### 5. `run<T>()` central invariant (repository.ts:2695)
```
if state !== Idle throw
try retryRun() → if !readOnly updateModelState(optimistic?)
catch: if NotAGitRepository → state=Disposed; if !readOnly updateModelState()
finally: operations.end + fire onDidRunOperation
```
Um lugar decide: retry, state machine, model refresh pós-op, auto-dispose em repo inválido.

**Zion hoje:** `refreshRepository cancelled` + `details.reload skipped (same commit)` mostra que parte disso existe. Falta `state = Disposed` automático quando git retorna `not a git repository` (log mostra 3 warns pro `liquid-flow-agent` que derivam daí).

### 6. Optimistic resource groups (repository.ts:1262)
Stage/unstage/restore/commit passam lambda `getOptimisticResourceGroups` — UI pinta estado previsto ANTES do status real voltar. `Operation.Add(!optimisticUpdateEnabled())` — spinner some quando otimismo ligado.

**Zion hoje:** stage/unstage espera `git status` completar → perceptível. Aplicar ao botão Stage, Discard, Commit daria sensação "instantâneo".

### 7. `GIT_OPTIONAL_LOCKS=0` em status (git.ts:2745)
```
env: { GIT_OPTIONAL_LOCKS: '0' }
args: ['status', '-z', '-uall' | '-uno', ...]
return { status, statusLength, didHitLimit }
```
Status não pega lock do index → nunca bloqueia commit/add paralelo. Retorna `didHitLimit` → UI pode avisar "repo muito grande".

**Zion hoje:** verificar `GitClient.status()` — se não passa `GIT_OPTIONAL_LOCKS=0`, adicionar. Ganho real em repos grandes durante fetch/commit concorrente.

### 8. AutoFetcher idle-aware (autofetch.ts)
- `Promise.race([timeout(period), whenDisabled])` → responde instantâneo a toggle off.
- `env.onDidChangeMeteredConnection` → pausa em celular.
- Só arma depois de `onFirstGoodRemoteOperation` — não gasta ciclos em remote quebrado.
- `DidInformUser` Memento para não spammar aviso.

**Zion hoje:** verificar se auto-fetch para em background / conexão medida. Metered detection no macOS via `NWPathMonitor.currentPath.isExpensive`.

## Ações sugeridas pro Zion (priorizadas)

1. **Adicionar `GIT_OPTIONAL_LOCKS=0`** em `GitClient.status()` — 1 linha, impacto imediato.
2. **Tipificar Operation kind** em `runGitAction` (enum com flags) — base pra tudo abaixo.
3. **`@throttle`/`@debounce` wrappers Swift** — property wrappers sobre `Task` + `actor`.
4. **Idle-and-focused gate** no `refreshRepository(origin: .fileWatcher)` — pular quando `NSApp.isActive == false` ou op em voo.
5. **Optimistic UI** em Stage/Unstage/Discard — passar `predictedStatus` para view antes do refetch real.
6. **Watcher filtrar `index.lock` e `.git/objects/pack/*.pack.tmp`** — reduzir ruído.
7. **Auto-dispose** de repo quando git retorna `not a git repository` — evita os 3 warns por refresh no log.

## Não aplicável (ou já temos equivalente)

- VS Code usa `workspace.createFileSystemWatcher` (VS Code API) — Zion já tem seu FS watcher.
- `withProgress({ location: ProgressLocation.SourceControl })` — Zion tem status bar busy indicator.
- `parentRepository` Memento anti-reprompt — caso de uso workspace-folders, não se aplica.
