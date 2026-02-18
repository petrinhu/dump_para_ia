# Orientações para Agentes e Modelos de Linguagem

Este projeto foi projetado para facilitar a retomada e continuação de desenvolvimento por modelos de linguagem (LLMs) em conversas longas ou reiniciadas.

## Como usar o dump com agentes

1. Envie o dump completo (arquivo .md gerado por dump_tree.sh -g -t)
   - Inclui árvore de diretórios + conteúdo de arquivos + instruções explícitas
   - Leia primeiro a seção "## Instruções para retomada do projeto"

2. Forneça contexto adicional quando necessário
   - Use a variável COMENTARIO para adicionar estado mental atual:
     COMENTARIO="implementar suporte a namespaces" ./dump_tree.sh -g -t

3. Boas práticas para interação com IA
   - Pergunte de forma específica e incremental
   - Referencie arquivos pelo caminho relativo (ex: "analise dump_tree.sh")
   - Peça verificações de consistência antes de gerar código novo
   - Se o dump for grande, peça análise por partes

4. Limitações conhecidas
   - Dump não inclui binários nem arquivos excluídos (-d, -e)
   - Estimativa de tokens é aproximada (bytes / 4)
   - Verifique sempre integridade com ./dump_tree.sh -v
