# CodeLab

App iOS para **aprender a programar direto do iPhone**, mesmo em aparelhos antigos (feito para iPhone 6s / iOS 15.x, instalado via TrollStore).

O iPhone não compila C++, Java, Kotlin, Android etc. sozinho. Por isso o CodeLab funciona assim:

> **Você escreve o código no app → envia para o GitHub (com git) → o GitHub compila/executa → o app mostra o resultado.**

## O que o app faz

| Opção | O que acontece |
|---|---|
| **C / C++** | `g++` no GitHub (compila todos os `.cpp` do projeto, inclusive em subpastas) e executa. |
| **Java** | `javac` + `java` no GitHub (todos os `.java`). |
| **Kotlin** | `kotlinc` no GitHub (todos os `.kt`) e executa. |
| **Godot** | Roda o script `main.gd` com Godot 4 (modo headless). |
| **Android** | Projeto Gradle vazio (estilo Android Studio) → monta o **APK**. |
| **iOS** | Projeto SwiftUI vazio (XcodeGen) → monta o **IPA sem assinatura**. |
| **Terminal** | Terminal com **git de verdade conectado ao GitHub**, dicas e corretor de comandos. |

## Abrir projetos que você já tem

- Botão **⤓** no menu principal: escolha um **.zip** ou uma **pasta** (a linguagem é detectada sozinha).
- Dentro de cada linguagem: **Abrir projeto existente (.zip ou pasta)**.
- Zips do GitHub (com uma pasta única dentro) são abertos sem a pasta extra; `__MACOSX`, `.DS_Store` e `.git` são ignorados.
- Alternativa: copie a pasta pelo app **Arquivos → No meu iPhone → CodeLab → Projects → (linguagem)**.

## Editor

Cores de sintaxe, **barra de símbolos** acima do teclado (`{ } ( ) ; : " ...`), Tab e auto-indentação. O botão **Corrigir** usa o corretor simples (parênteses/chaves sem par, `;` ou `:` faltando). Ele **não é um compilador**: o erro de verdade aparece na saída do GitHub.

## Terminal e git

O terminal **não executa programas do iOS** (o iOS não permite, e não existem `apt`, `gcc`, `sudo` etc. no aparelho). Em vez disso, o CodeLab implementa os comandos por dentro, falando com a API do GitHub:

```
git init                       cria o repositório na pasta
git clone usuario/repo         baixa um repositório
git remote add origin repo     liga a pasta ao GitHub
git status | add | commit -m   o ciclo normal do git
git push | pull | log          envia / baixa / histórico
git diff | branch | reset | rm
run                            compila/executa no GitHub e mostra a saída
ls cd pwd tree cat head tail grep wc mkdir touch rm mv cp echo clear ...
```

- `git push` envia **um commit real por commit local** (blobs → árvore → commit → branch), com a sua mensagem.
- `&&` funciona: `git add . && git commit -m "ok" && git push`.
- **Indicador de próximo passo** (💡), **sugestões** tocáveis e **corretor** ("Você quis dizer git commit?") aparecem enquanto você digita. O botão **?** abre a lista completa.
- Não suportado ainda: `checkout`, `switch`, `restore`, `merge`, `rebase`, `stash`, `fetch`, `tag` (o app avisa).

### Fluxo básico

```
cd cpp/meuprojeto
git init
git remote add origin meu-usuario/meuprojeto
git add .
git commit -m "primeira versão"
git push
run
```

## Como usar

1. No GitHub: Settings → Developer settings → Personal access tokens (classic), com **`repo`** e **`workflow`**.
2. No app, **Entrar no GitHub** e cole o token.
3. Escolha a linguagem, crie/abra um projeto, edite.
4. Use o terminal (`git ...` e `run`) **ou** os botões do projeto (Enviar / Executar), que fazem o mesmo.
5. APK/IPA gerados são baixados para **Arquivos → CodeLab → Downloads** (toque no .zip para abrir). O IPA não é assinado: instale pelo TrollStore.

## Limitações conhecidas

- Nada é compilado no aparelho; depende de internet e do GitHub Actions (1 a 5 minutos).
- `run` executa o **projeto inteiro** no GitHub, não um trecho isolado.
- `git diff` mostra só um resumo por arquivo; sem `restore`/branches múltiplas.
- Zip64 e métodos de compressão raros não são suportados na importação.
- O token fica em `UserDefaults` (não no Keychain): use um token com validade curta.

## Estrutura

```
project.yml                    projeto (XcodeGen)
.github/workflows/build.yml    gera o IPA do próprio CodeLab
CodeLab/
  CodeLabApp.swift   Views.swift   CodeEditor.swift
  Models.swift       Templates.swift   Linter.swift
  GitEngine.swift    (git local: status/add/commit)
  GitHub.swift       (API: push/pull/clone/log/run)
  Terminal.swift     (comandos, dicas, corretor)
  Importer.swift     (abrir .zip e pastas)
  Assets.xcassets/   ícone
```
