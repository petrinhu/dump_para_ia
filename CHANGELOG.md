# CHANGELOG — dump_tree.sh

Repositório: https://github.com/petrinhu/dump_para_ia

## [Unreleased]

Nenhuma mudança pendente.

## [0.2.0] - 2026-02-18

### Added
- Flag `-f` / `--force`: força a geração do dump mesmo quando a pasta não é detectada como projeto
- Flag `-y` / `--yes`: responde sim a todas as confirmações interativas
- Flag `-q` / `--quiet`: modo silencioso sem cores, sem interação e sem progresso (implica `-y`); adequado para CI e scripts
- Opções longas `--force`, `--yes`, `--quiet` como aliases das flags curtas
- Detecção automática do dump com timestamp mais recente no modo `-v` quando `dump.md` não existe
- Info de git (branch e commit curto) na tabela de cabeçalho do dump
- Suporte a `go.mod` como sinal de alto nível na detecção de projeto
- `detect_language` expandida com 20+ extensões: `.rs`, `.go`, `.ts`, `.java`, `.rb`, `.php`, `.cs`, `.kt`, `.lua`, `.r`, `.sql`, `.tf`, `.toml`, `.ini`, `.env`, `Dockerfile`

### Changed
- Formato de saída migrado de texto plano (`.txt`) para **Markdown limpo** (`.md`) com tabelas e blocos de código com highlight por linguagem
- `detect_language` agora retorna identificadores de bloco Markdown (`bash`, `cpp`, `python`, etc.) em vez de labels legíveis
- Estimativa de tokens corrigida de `bytes / 4` para `bytes * 2 / 7` (~3.5 bytes/token), mais precisa para texto em PT-BR/UTF-8
- `check_and_install_deps` movida para após o parse de `-h` / `--help`: ajuda nunca bloqueia para instalar dependências
- `sudo` removido da lista de dependências obrigatórias
- Loop de processamento de arquivos refatorado em função `processar_arquivo()`, eliminando duplicação entre dry-run e geração
- Lógica de confirmação de projeto extraída para função `confirmar()` reutilizável
- Sinais de linguagem de nível médio expandidos com Ruby, PHP, Kotlin, C#, Lua

### Fixed
- Parêntese faltando na expansão de subshell `$(detect_language ...)` que causava syntax error no modo `-g`
- Conteúdo corrompido após a linha final do script (bloco do script embutido dentro de si mesmo via backticks)
- `sudo cat` substituído por `cat` simples — uso de sudo para leitura de arquivos do próprio projeto era desnecessário e inseguro

## [0.1.0] - 2026-02-18

### Added
- Geração de dump em Markdown com estrutura de diretórios via `tree`
- Detecção de linguagem para blocos de código
- Dry-run (`-n`) para auditoria sem geração de arquivo
- Verificação de integridade SHA-256 (`-v`)
- Limite de tokens (`--max-tokens`)
- Instalação automática de dependências para Fedora, Ubuntu/Debian, Arch e openSUSE
- Suporte a subdiretório específico (`-o`) e exclusões extras (`-e`)
- Exclusão de docs com `-d`
- Variável de ambiente `COMENTARIO` para contexto de retomada por IA
- Seção "Instruções para retomada do projeto" no cabeçalho do dump
- Info de git (commit e branch) no cabeçalho
- Log de execução em arquivo `.log`
- Timestamp opcional no nome dos arquivos gerados (`-t`)
- Detecção heurística de projeto com três níveis de sinal (alto, médio, baixo)
- Detecção de distro via `/etc/os-release` com suporte a `ID_LIKE`
