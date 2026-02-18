# Política de Segurança

## Reportar uma vulnerabilidade

Se você encontrar uma vulnerabilidade de segurança, **não abra uma issue pública**.

Envie um email para **petrinhu@yahoo.com.br** com:

- Descrição detalhada da vulnerabilidade
- Passos para reproduzir
- Impacto potencial
- Sugestão de correção (opcional)

## Escopo

Vulnerabilidades cobertas por esta política:

- Execução arbitrária de código via argumentos ou variáveis de ambiente do script
- Exposição de dados sensíveis do sistema durante a execução
- Escalada de privilégios

Fora do escopo:

- Corrupção de dump gerado localmente (coberta pela verificação SHA-256 via `./dump_tree.sh -v`)
- Problemas em versões de Bash anteriores à 4.0 (fora dos requisitos do projeto)

## Processo e prazos

| Severidade | Prazo de resposta | Prazo de correção |
|---|---|---|
| Crítica | 24h | 7 dias |
| Alta | 48h | 30 dias |
| Média/Baixa | 72h | 90 dias |

Após a correção, o relator recebe crédito no CHANGELOG e na release correspondente, se desejar.

Agradecemos por ajudar a manter o projeto seguro.
