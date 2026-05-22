# Plano de Implementação: Suporte a LLM Local no Zion

## Visão Geral

O Zion atualmente usa APIs externas (Anthropic, OpenAI, Gemini) para todas as funcionalidades de IA. Este plano descreve como adicionar suporte para rodar LLMs localmente, permitindo que usuários usem modelos open-source como Llama 3, Mistral, Phi, etc., sem depender de APIs externas.

---

## Arquitetura Atual

### Componentes Existentes

1. **`AIClient`** (Services/AIClient.swift)
   - Actor que gerencia chamadas de IA
   - Métodos: `generateCommitMessage`, `generatePRDescription`, `explainDiff`, etc.
   - Usa `call()` para rotear para provedores específicos

2. **`AIProvider`** (Models/AppEnums.swift)
   - Enum: `.none, .anthropic, .openai, .gemini`
   - Cada provedor tem implementação HTTP específica

3. **`AIProviderSupport`** (Services/AIProviderSupport.swift)
   - Gerencia conexão e chaves de API
   - `configurableProviders = [.anthropic, .openai, .gemini]`

4. **`AIModelCatalogService`** (Services/AIModelCatalogService.swift)
   - Mapeia `mode` + `lane` → model IDs
   - Ex: `.efficient` + `.general` → `gpt-4o-mini`

5. **`AISettingsTab`** (Views/Settings/AISettingsTab.swift)
   - UI para configurar provedor, chave API, modo

---

## Arquitetura Proposta

### Nova Estrutura

```
AIProvider
├── .anthropic (API externa)
├── .openai (API externa)
├── .gemini (API externa)
└── .local (NOVO - LLM local)

LocalLLMConfig (NOVO)
├── backend: .llamaCpp | .ollama | .openAILocal
├── modelPath: String (caminho para .gguf ou nome do modelo)
├── serverURL: URL (para backends com servidor)
├── contextWindow: Int
└── gpuLayers: Int (para offload GPU)
```

---

## Backends Locais Suportados

### 1. **Ollama** (Recomendado - Mais Simples)
- **Protocolo**: HTTP REST API compatível com OpenAI
- **URL padrão**: `http://localhost:11434`
- **Modelos**: `llama3.2`, `mistral`, `phi3`, `gemma2`
- **Vantagens**: 
  - API compatível com OpenAI (reusa `callOpenAI`)
  - Gerencia download de modelos automaticamente
  - Fácil de configurar
- **Requisitos**: Usuário instala Ollama separadamente

### 2. **llama.cpp Server**
- **Protocolo**: HTTP REST API compatível com OpenAI
- **URL padrão**: `http://localhost:8080`
- **Modelos**: Arquivos `.gguf`
- **Vantagens**: 
  - Controle total sobre modelo e parâmetros
  - API compatível com OpenAI
- **Requisitos**: Usuário baixa modelo `.gguf` e roda servidor

### 3. **LM Studio**
- **Protocolo**: HTTP REST API compatível com OpenAI
- **URL padrão**: `http://localhost:1234`
- **Vantagens**: 
  - GUI amigável para gerenciar modelos
  - API compatível com OpenAI
- **Requisitos**: Usuário instala LM Studio

### 4. **Integração Nativa llama.cpp** (Avançado)
- **Protocolo**: Link direto com biblioteca `llama.cpp`
- **Vantagens**: 
  - Sem servidor intermediário
  - Menor latência
- **Desvantagens**: 
  - Requer embedar biblioteca C++ no app
  - Maior complexidade de build
  - App Store review pode rejeitar

---

## Plano de Implementação

### Fase 1: Backend Ollama (MVP) ⭐

**Objetivo**: Suporte básico a Ollama usando API compatível com OpenAI

#### Arquivos a Criar/Modificar

1. **`Models/AppEnums.swift`**
   ```swift
   enum AIProvider: String, CaseIterable, Identifiable {
       case none, anthropic, openai, gemini, local
       
       var label: String {
           switch self {
           case .local: return L10n("Local (Ollama/llama.cpp)")
           // ... outros casos
           }
       }
   }
   
   enum LocalLLMBackend: String, CaseIterable, Identifiable {
       case ollama, llamaCppServer, lmStudio, customOpenAI
       
       var label: String {
           switch self {
           case .ollama: return L10n("Ollama")
           case .llamaCppServer: return L10n("llama.cpp Server")
           case .lmStudio: return L10n("LM Studio")
           case .customOpenAI: return L10n("Custom OpenAI-compatible")
           }
       }
       
       var defaultURL: String {
           switch self {
           case .ollama: return "http://localhost:11434"
           case .llamaCppServer: return "http://localhost:8080"
           case .lmStudio: return "http://localhost:1234"
           case .customOpenAI: return ""
           }
       }
   }
   ```

2. **`Models/AIModels.swift`**
   ```swift
   struct LocalLLMConfig: Codable, Equatable {
       var backend: LocalLLMBackend = .ollama
       var serverURL: String = "http://localhost:11434"
       var modelName: String = "llama3.2"
       var contextWindow: Int = 8192
       var gpuLayers: Int = -1  // -1 = auto
       var apiKey: String = ""  // opcional, alguns servidores requerem
       
       var endpointURL: URL? {
           URL(string: serverURL)
       }
   }
   ```

3. **`Services/AIClient.swift`**
   - Adicionar caso `.local` no switch do `call()`
   - Implementar `callLocalLLM()` reusando lógica do OpenAI
   
   ```swift
   case .local:
       return try await callLocalLLM(
           payload: payload, 
           config: localConfig, 
           maxTokens: maxTokens, 
           modelID: modelID
       )
   ```

4. **`Services/AIClient+Local.swift`** (NOVO)
   ```swift
   extension AIClient {
       
       static let localConfigKey = "com.zion.ai.local-config"
       
       static func saveLocalConfig(_ config: LocalLLMConfig) {
           UserDefaults.standard.set(
               try? JSONEncoder().encode(config),
               forKey: localConfigKey
           )
       }
       
       static func loadLocalConfig() -> LocalLLMConfig? {
           guard let data = UserDefaults.standard.data(forKey: localConfigKey),
                 let config = try? JSONDecoder().decode(LocalLLMConfig.self, from: data)
           else { return nil }
           return config
       }
       
       func callLocalLLM(
           payload: AIPromptPayload,
           config: LocalLLMConfig,
           maxTokens: Int,
           modelID: String
       ) async throws -> String {
           
           // Usa API compatível com OpenAI
           let url = URL(string: "\(config.serverURL)/v1/chat/completions")!
           var request = URLRequest(url: url)
           request.httpMethod = "POST"
           request.setValue("application/json", forHTTPHeaderField: "Content-Type")
           
           if !config.apiKey.isEmpty {
               request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
           }
           
           request.timeoutInterval = 60  // LLMs locais podem ser mais lentos
           
           let body = Self.openAIRequestBody(
               payload: payload, 
               maxTokens: maxTokens, 
               modelID: modelID
           )
           request.httpBody = try JSONSerialization.data(withJSONObject: body)
           
           let (data, response) = try await URLSession.shared.data(for: request)
           guard let http = response as? HTTPURLResponse else { 
               throw AIError.localConnectionFailed 
           }
           
           if http.statusCode == 404 {
               throw AIError.localServerNotFound
           }
           if http.statusCode == 500 {
               throw AIError.localModelError
           }
           guard http.statusCode == 200 else {
               throw AIError.localAPIError("Local LLM failed (\(http.statusCode))")
           }
           
           let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
           guard let choices = json?["choices"] as? [[String: Any]],
                 let message = choices.first?["message"] as? [String: Any],
                 let text = message["content"] as? String else {
               throw AIError.invalidResponse
           }
           
           return text.trimmingCharacters(in: .whitespacesAndNewlines)
       }
   }
   ```

5. **`Services/AIProviderSupport.swift`**
   ```swift
   enum AIProviderSupport {
       static let configurableProviders: [AIProvider] = [.anthropic, .openai, .gemini, .local]
       
       static func isConnected(provider: AIProvider) -> Bool {
           switch provider {
           case .local:
               return testLocalConnection()
           default:
               // lógica existente
           }
       }
       
       private static func testLocalConnection() -> Bool {
           guard let config = AIClient.loadLocalConfig(),
                 let url = config.endpointURL else { return false }
           
           // Testa com request simples
           let testURL = URL(string: "\(url)/api/tags")!  // Ollama
           // ... implementa teste de conexão
       }
   }
   ```

6. **`Services/AIModelCatalogService.swift`**
   ```swift
   case .local:
       return localSelection(mode: mode, lane: lane)
   
   private static func localSelection(mode: AIMode, lane: AITaskLane) -> AIResolvedModelSelection {
       // Para local, usa o modelo configurado pelo usuário
       guard let config = AIClient.loadLocalConfig() else {
           return AIResolvedModelSelection(lane: lane, primaryModelID: "", fallbackModelIDs: [])
       }
       
       // LLMs locais geralmente usam o mesmo modelo para todas as tarefas
       return makeSelection(
           lane: lane, 
           primary: config.modelName, 
           fallbacks: []
       )
   }
   ```

7. **`Views/Settings/AISettingsTab.swift`**
   - Adicionar seção para configurar LLM local quando `aiProvider == .local`
   - Picker para backend (Ollama, llama.cpp, etc.)
   - TextField para URL do servidor
   - TextField para nome do modelo
   - Slider para context window
   - Button para "Testar Conexão"

8. **`AIError`** (Services/AIClient+Helpers.swift)
   ```swift
   enum AIError: LocalizedError {
       // ... casos existentes
       case localConnectionFailed
       case localServerNotFound
       case localModelError
       case localAPIError(String)
       
       var errorDescription: String? {
           switch self {
           case .localConnectionFailed: 
               return L10n("Nao foi possivel conectar ao servidor local")
           case .localServerNotFound:
               return L10n("Servidor local nao encontrado. Verifique se esta rodando.")
           case .localModelError:
               return L10n("Erro no modelo local. Verifique se o modelo esta carregado.")
           case .localAPIError(let msg): return msg
           // ... outros casos
           }
       }
   }
   ```

9. **Localization Files**
   - Adicionar strings para `en`, `pt-BR`, `es` em `Resources/Localization/`

---

### Fase 2: Melhorias e UX

1. **Detecção Automática de Ollama**
   - Tentar conectar em `http://localhost:11434` automaticamente
   - Sugerir instalação do Ollama se não encontrado

2. **Lista de Modelos Disponíveis**
   - Para Ollama: chamar `/api/tags` para listar modelos
   - Picker dinâmico de modelos

3. **Teste de Conexão**
   - Button "Testar Conexão" que faz request simples
   - Feedback visual de sucesso/erro

4. **Timeouts Ajustáveis**
   - LLMs locais podem ser lentos (30-60s)
   - Permitir configurar timeout

5. **Streaming de Resposta**
   - Implementar streaming para feedback em tempo real
   - Mostrar texto sendo gerado caractere por caractere

---

### Fase 3: Recursos Avançados

1. **Integração Nativa llama.cpp**
   - Embedar biblioteca no app
   - Download de modelos `.gguf` direto do app
   - **Desafio**: App Store pode rejeitar

2. **Gerenciador de Modelos**
   - UI para baixar/atualizar modelos
   - Integração com Hugging Face

3. **Configurações Avançadas**
   - Temperature, top_p, repetition_penalty
   - System prompt customizável

4. **Benchmarks Locais**
   - Medir velocidade (tokens/segundo)
   - Sugerir modelos otimizados

---

## Modelos Recomendados para Uso Local

| Modelo | Tamanho | RAM | Velocidade | Qualidade | Uso Ideal |
|--------|---------|-----|------------|-----------|-----------|
| **Llama 3.2 3B** | 2GB | 4GB | Muito rápida | Boa | Commits rápidos |
| **Llama 3.2 1B** | 1GB | 2GB | Extremamente rápida | Básica | Commits simples |
| **Phi 3 Mini** | 2GB | 4GB | Muito rápida | Boa | Geral |
| **Mistral 7B** | 4GB | 8GB | Rápida | Muito boa | Reviews, PRs |
| **Gemma 2 9B** | 5GB | 8GB | Rápida | Muito boa | Reasoning |
| **Llama 3.1 8B** | 4GB | 8GB | Rápida | Excelente | Geral |

**Recomendação inicial**: `llama3.2:3b` ou `llama3.2:1b` para maioria dos usuários

---

## Riscos e Mitigações

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| App Store rejeita (llama.cpp embedded) | Alto | Usar apenas backends externos (Ollama, etc.) |
| Usuário não sabe configurar | Médio | UI clara, detecção automática, docs |
| Performance lenta | Médio | Timeout ajustável, streaming, warnings |
| Qualidade inferior a APIs | Médio | Deixar claro nas UI, permitir alternar |
| Privacidade vazada | Baixo | LLM local = dados nunca saem do machine |

---

## Cronograma Estimado

| Fase | Tempo | Entrega |
|------|-------|---------|
| **Fase 1 (MVP)** | 2-3 dias | Ollama básico funcionando |
| **Fase 2 (UX)** | 1-2 dias | Detecção automática, teste de conexão |
| **Fase 3 (Avançado)** | 3-5 dias | Streaming, configs avançadas |

**Total**: 6-10 dias de desenvolvimento

---

## Checklist de Implementação

### Fase 1 - MVP
- [ ] Adicionar `.local` ao `AIProvider`
- [ ] Criar `LocalLLMBackend` enum
- [ ] Criar `LocalLLMConfig` model
- [ ] Implementar `callLocalLLM()` em `AIClient`
- [ ] Adicionar caso `.local` em `AIModelCatalogService`
- [ ] Atualizar `AIProviderSupport` para incluir `.local`
- [ ] Adicionar UI em `AISettingsTab` para config local
- [ ] Adicionar novos `AIError` cases
- [ ] Adicionar strings de localization (en, pt-BR, es)
- [ ] Testar com Ollama + llama3.2

### Fase 2 - UX
- [ ] Detecção automática de Ollama
- [ ] Listar modelos disponíveis via API
- [ ] Button "Testar Conexão"
- [ ] Aumentar timeout padrão para 60s
- [ ] Mensagens de erro amigáveis

### Fase 3 - Avançado
- [ ] Streaming de resposta
- [ ] Configurações avançadas (temperature, etc.)
- [ ] Docs de usuário

---

## Referências

- **Ollama API**: https://github.com/ollama/ollama/blob/main/docs/api.md
- **llama.cpp Server**: https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md
- **LM Studio**: https://docs.lmstudio.ai/
- **Modelos GGUF**: https://huggingface.co/models?library=gguf

---

## Notas de Design

1. **API Compatível com OpenAI**: A maioria dos backends locais suporta API OpenAI, o que simplifica muito a implementação.

2. **Sem Dependências Binárias**: Evitar embedar `llama.cpp` no app para não ter problemas com App Store.

3. **Configuração Persistente**: Salvar config local em `UserDefaults` (não em keychain, não é segredo).

4. **Fallback Graceful**: Se servidor local cair, permitir alternar rápido para API externa.

5. **Privacidade First**: Destacar que LLM local = dados nunca saem do machine do usuário.
