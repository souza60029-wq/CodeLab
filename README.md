# CodeLab

App iOS para **programar direto do iPhone**, mesmo em aparelhos antigos (feito para iPhone 6s / iOS 15.x, instalado via TrollStore).

Como o iPhone não consegue compilar C++, Java, Kotlin, Android etc. sozinho, o CodeLab funciona assim:

> **Você escreve o código no app → o app envia para o GitHub → o GitHub compila/executa → o app mostra o resultado.**

## O que o app faz

| Opção | O que acontece |
|---|---|
| **C / C++** | Cria projeto com `main.cpp`. O GitHub compila com `g++` e executa. |
| **Java** | Cria `Main.java`. O GitHub roda `javac` + `java`. |
| **Kotlin** | Cria `Main.kt`. O GitHub baixa o `kotlinc`, compila e executa. |
| **Godot** | Cria `project.godot` + `main.gd`. O GitHub roda o script com Godot 4 (modo headless). |
| **Android** | Cria um projeto Gradle vazio (estilo Android Studio, com pastas `app/src/main/...`). O GitHub monta o **APK**. |
| **iOS** | Cria um projeto SwiftUI vazio (XcodeGen). O GitHub (macOS) monta um **IPA sem assinatura**. |
| **Terminal** | Mini terminal **local e simulado** (veja abaixo). |

Também tem:

- **Editor de texto** com salvamento automático.
- **Corretor simples** (`Corrigir`): detecta parênteses/chaves sem par, `;` faltando em C/C++/Java e `:` faltando em GDScript. É uma checagem básica, **não é um compilador** — pode errar. O erro "de verdade" aparece no resultado do GitHub.
- **Login no GitHub** por token de acesso pessoal.
- **Enviar pro GitHub** (cria o repositório privado se não existir) e **Executar / Montar APK / Montar IPA** (envia, dispara o workflow e mostra o resultado no app).

## Como usar

1. Em github.com → Settings → Developer settings → Personal access tokens (classic), crie um token marcando **`repo`** e **`workflow`**.
2. No app, toque em **Entrar no GitHub** e cole o token.
3. Escolha uma linguagem → crie um projeto → edite os arquivos.
4. Digite o nome do repositório e toque em **Executar / compilar** (ou **Montar APK / IPA**).
5. Para APK/IPA: abra a execução no GitHub → **Artifacts** e baixe o arquivo.

> O IPA gerado não é assinado. No iPhone com TrollStore, basta abri-lo com o TrollStore para instalar.

## Terminal: por que `sudo` e `apt` não funcionam?

O terminal do CodeLab **não é um terminal de verdade**. Ele é um mini-interpretador escrito em Swift que entende só estes comandos:

`help pwd ls cd cat mkdir touch rm mv cp echo wc clear`

e só enxerga a pasta de projetos do próprio app. Qualquer outro comando (`sudo`, `apt`, `git`, `gcc`, `python`...) cai em "comando não encontrado", porque:

1. O app **não executa programas externos** — ele só imita alguns comandos.
2. O iOS **não tem** `apt`, `sudo`, `gcc` etc. instalados de fábrica; esses programas não existem no aparelho.
3. O sandbox do iOS impede apps normais de abrir outros processos.

Para ter um shell completo seria preciso outro caminho (ex.: um ambiente Linux por SSH em um servidor, ou um app com bootstrap próprio). Isso não faz parte desta versão.

## Limitações conhecidas

- Nada é compilado no aparelho; sempre depende de internet e do GitHub Actions (leva de ~1 a 5 minutos).
- "Executar" roda o **projeto inteiro** no GitHub, não um trecho isolado.
- C/C++ e Java compilam só arquivos da **raiz** do projeto (`*.cpp`, `*.java`).
- O token do GitHub fica salvo em `UserDefaults` (não no Keychain). Use um token com validade curta.
- O envio manda um arquivo por vez (um commit por arquivo) — lento em projetos grandes.
- Sem destaque de sintaxe nem numeração de linhas no editor.

## Estrutura do repositório

```
CodeLab/
├── project.yml              # definição do projeto (XcodeGen)
├── .github/workflows/build.yml   # gera o IPA do próprio CodeLab
└── CodeLab/
    ├── CodeLabApp.swift     # ponto de entrada
    ├── Views.swift          # telas (menu, projetos, editor, login)
    ├── Models.swift         # linguagens e armazenamento de projetos
    ├── Templates.swift      # arquivos iniciais e workflows de cada linguagem
    ├── GitHub.swift         # API do GitHub (login, envio, workflow, logs)
    ├── Linter.swift         # corretor simples
    ├── Terminal.swift       # terminal simulado
    └── Assets.xcassets/     # ícone do app
```

## Compilar o próprio CodeLab

O workflow `.github/workflows/build.yml` roda a cada push na `main` (ou manualmente em **Actions → Build IPA → Run workflow**) e publica o `CodeLab.ipa` em Artifacts.
