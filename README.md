# dump_tree.sh

Ferramenta em Bash para gerar dumps completos de projetos em formato Markdown, otimizada para envio a modelos de linguagem (LLMs) em cenários de retomada de contexto ou continuação de projetos longos.

O dump inclui:

- Estrutura de diretórios (via `tree`)
- Conteúdo de todos os arquivos textuais relevantes, com blocos de código e highlight de linguagem
- Metadados úteis para retomada por IA (comentário opcional, commit git, branch, arquivos excluídos, etc.)
- Resumo final com contagem de arquivos, tamanho, tokens estimados e instruções de verificação

Ideal para quando você precisa enviar o estado atual do projeto para uma IA sem depender de memória de conversa anterior.

## Características principais

- Formato de saída: Markdown limpo (`.md`) com highlight de linguagem por arquivo
- Detecção automática de linguagem para blocos de código (30+ extensões suportadas)
- Exclusão inteligente de diretórios comuns (`.git`, `build`, `.cache`, `Testing`, etc.)
- Suporte a subdiretório específico (`-o`), exclusões extras (`-e`), limite de tokens (`--max-tokens`)
- Dry-run (`-n`) para auditoria sem gerar arquivo
- Verificação de integridade via SHA-256 (`-v`)
- Modo não-interativo (`-f`, `-y`, `-q`) para uso em scripts e CI
- Instalação automática de dependências em distros comuns (Fedora, Ubuntu/Debian, Arch, openSUSE)
- Comentário opcional via variável de ambiente (`COMENTARIO="texto" ./dump_tree.sh -g -t`)
- Instruções explícitas para retomada por IA no cabeçalho do dump
- Suporte a git (commit e branch atual, se repositório existir)

## Requisitos

- Bash 4+
- Dependências básicas (instaladas automaticamente na primeira execução):
  - `tree`
  - `file`
  - `sha256sum`
  - `tput`
  - `find`, `stat`

## Instalação

1. Clone este repositório ou baixe o arquivo `dump_tree.sh`
2. Dê permissão de execução:

```bash
chmod +x dump_tree.sh
```

3. (Opcional) Mova para um diretório no PATH:

```bash
sudo cp dump_tree.sh /usr/local/bin/dump_tree
```

## Uso básico

```bash
./dump_tree.sh -g -t
```

## Opções completas

| Opção | Descrição |
|---|---|
| `-g` | Gera o dump (modo principal) |
| `-n` | Dry-run: lista arquivos sem gerar dump |
| `-t` | Timestamp no nome do arquivo de saída |
| `-d` | Exclui `docs/`, `*.md`, `LICENSE`, `CHANGELOG*` |
| `-o <subpasta>` | Processa apenas a subpasta especificada |
| `-e <pasta>` | Exclui pasta adicional (repetível) |
| `-f` / `--force` | Força geração mesmo sem sinais de projeto |
| `-y` / `--yes` | Responde sim a todas as confirmações interativas |
| `-q` / `--quiet` | Modo silencioso: sem cores, sem interação (implica `-y`) |
| `--max-tokens N` | Aborta se estimativa de tokens ultrapassar N |
| `-v` | Verifica SHA-256 do dump gerado |
| `-h` / `--help` | Ajuda completa |

## Variáveis de ambiente

| Variável | Descrição |
|---|---|
| `COMENTARIO` | Texto livre incluído no cabeçalho do dump como contexto de retomada |

Exemplo:

```bash
COMENTARIO="travado no parser XML, função parse_node está retornando nil" ./dump_tree.sh -g -t
```

## Exemplos de uso

```bash
# Dump completo com timestamp
./dump_tree.sh -g -t

# Auditar sem gerar arquivo
./dump_tree.sh -g -n

# Apenas o diretório src/, sem docs
./dump_tree.sh -g -d -o src

# Excluir pastas extras
./dump_tree.sh -g -e vendor -e third_party

# Forçar geração em pasta sem sinais de projeto
./dump_tree.sh -g -f

# Uso em script/CI (sem interação)
./dump_tree.sh -g -t -q

# Limitar tamanho do dump
./dump_tree.sh -g --max-tokens 80000

# Verificar integridade do dump gerado
./dump_tree.sh -v
```

## Exemplo de dump gerado

O dump gerado é um arquivo `.md` com a seguinte estrutura:

**Cabeçalho com metadados:**

| Campo | Valor |
|---|---|
| **Diretório raiz** | `/home/user/meu_projeto` |
| **Gerado em** | `2026-02-18T15:42:03-0300` |
| **Distro** | `fedora` |
| **Total de arquivos** | `9` |
| **Git** | `main @ a1b2c3d` |
| **Excluídos** | `build .git .cache Testing` |

**Comentário do desenvolvedor** (quando `COMENTARIO` está definido):

> versão inicial com instruções para IA

**Estrutura de diretórios** (bloco `tree`):

```
.
├── AGENTS.md
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── dump_tree.sh
├── .gitignore
├── LICENSE
├── README.md
└── SECURITY.md
```

**Conteúdo de cada arquivo** em bloco de código com highlight por linguagem:

```bash
#!/usr/bin/env bash
# dump_tree.sh
...
```

**Resumo final** com contagem de arquivos, tamanho e tokens estimados.

## Arquivos gerados

| Arquivo | Descrição |
|---|---|
| `dump.md` | Conteúdo completo do projeto em Markdown |
| `dump.md.sha256` | Checksum SHA-256 para verificação de integridade |
| `dump.log` | Log detalhado da execução |

Com `-t`, os nomes incluem timestamp: `dump_20260218_1542.md`, `dump_20260218_1542.md.sha256`, `dump_20260218_1542.log`.

## Licença

MIT License — veja [LICENSE](LICENSE) para detalhes.

## Contribuição

Abra issues ou pull requests. Veja [CONTRIBUTING.md](CONTRIBUTING.md) para detalhes.
