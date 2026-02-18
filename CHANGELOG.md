# CHANGELOG

Todas as mudanças notáveis serão documentadas neste arquivo no formato [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Suporte a variável COMENTARIO para contexto de retomada por IA
- Seção "## Instruções para retomada do projeto" no dump
- Lista de excluídos e git info no cabeçalho do dump
- Contagem de linhas totais aproximadas no resumo

### Changed
- Formato do dump para Markdown limpo com delimitadores ###
- Data em formato ISO 8601 completo

### Fixed
- Remoção de exemplos irrelevantes no README

## [0.1.0] - 2026-02-18

### Added
- Geração de dump em Markdown
- Detecção de linguagem para blocos de código
- Dry-run, verificação SHA-256, limite de tokens
- Instalação automática de dependências
