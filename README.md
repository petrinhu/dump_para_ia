# dump_tree.sh

Ferramenta em Bash para gerar dumps completos de projetos em formato Markdown, otimizada para envio a modelos de linguagem (LLMs) em cenários de retomada de contexto ou continuação de projetos longos.

O dump inclui:

- Estrutura de diretórios (via tree)
- Conteúdo de todos os arquivos textuais relevantes
- Metadados úteis para retomada por IA (instruções explícitas, comentário opcional, commit git, arquivos excluídos, etc.)
- Resumo final com contagem de arquivos, linhas, tokens estimados e instruções de verificação

Ideal para quando você precisa enviar o estado atual do projeto para uma IA sem depender de memória de conversa anterior.

## Características principais

- Formato de saída: Markdown limpo (.md) com delimitadores claros (### caminho/arquivo.ext)
- Detecção automática de linguagem para blocos de código com highlight correto
- Exclusão inteligente de diretórios comuns (.git, build, .cache, Testing, etc.)
- Suporte a subdiretório específico (-o), exclusões extras (-e), limite de tokens (--max-tokens)
- Dry-run (-n) para auditoria sem gerar arquivo
- Verificação de integridade via SHA-256 (-v)
- Instalação automática de dependências em distros comuns (Fedora, Ubuntu/Debian, Arch, openSUSE)
- Comentário opcional via variável de ambiente (COMENTARIO="texto" ./dump_tree.sh -g -t)
- Instruções explícitas para retomada por IA no cabeçalho do dump
- Suporte a git (commit e branch atual, se repositório existir)

## Requisitos

- Bash 4+
- Dependências básicas (instaladas automaticamente na primeira execução):
  - tree
  - file
  - sha256sum
  - tput
  - find, stat, sudo

## Instalação

1. Clone este repositório ou baixe o arquivo dump_tree.sh
2. Dê permissão de execução:

chmod +x dump_tree.sh

3. (Opcional) Mova para um diretório no PATH:

sudo cp dump_tree.sh /usr/local/bin/dump_tree

## Uso básico

./dump_tree.sh -g -t

## Opções completas

Opção               Descrição
-g                  Gera o dump (modo principal)
-n                  Dry-run
-t                  Timestamp no nome
-d                  Exclui docs/, *.md, LICENSE, CHANGELOG*
-o <subpasta>       Processa apenas subpasta
-e <pasta>          Exclui pasta adicional
--max-tokens N      Limite de tokens
-v                  Verifica SHA-256
-h                  Ajuda

## Exemplo de dump gerado (baseado na estrutura real do projeto)

# Dump do Projeto: dump_tree
Diretório raiz: ./projeto_dump
Gerado em (ISO): 2026-02-18T15:42:03-03:00
Distro        : fedora
Comentário    : versão inicial com instruções para IA

## Instruções para retomada do projeto
Este é um dump completo de um projeto. Você está retomando do zero.
- Leia primeiro a estrutura de diretórios (tree).
- Depois leia os arquivos na ordem apresentada.
- Considere o comentário como o último estado mental do desenvolvedor.
- Pergunte apenas o essencial; evite suposições.
- Foque em continuar de onde parou.

## Estrutura do Projeto (tree)

.
├── AGENTS.md
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── dump_tree.sh
├── LICENSE
├── README.md
├── SECURITY.md

## Conteúdo dos Arquivos

---

### dump_tree.sh

#!/usr/bin/env bash
etc etc (leia o arquivo)

...

## Resumo Final
Arquivos incluídos     : 9
Binários ignorados     : 0
Linhas totais aproximadas: ~800
Tokens estimados       : ~3200

## Verificação de Integridade
Checksum SHA-256 salvo em: dump_20260218_1542.md.sha256
Execute: sha256sum -c dump_20260218_1542.md.sha256

Licença

MIT License

Contribuição

Abra issues ou pull requests para melhorias.
