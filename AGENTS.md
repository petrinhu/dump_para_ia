# Orientações para Agentes e Modelos de Linguagem

Este projeto foi projetado para facilitar a retomada e continuação de desenvolvimento por modelos de linguagem (LLMs) em conversas longas ou reiniciadas.

## Como usar o dump com agentes

1. Envie o dump completo (arquivo `.md` gerado por `dump_tree.sh -g -t`)
   - Inclui árvore de diretórios + conteúdo de arquivos com highlight de linguagem + instruções explícitas
   - Leia primeiro a seção `## Instruções para retomada do projeto`

2. Forneça contexto adicional quando necessário
   - Use a variável `COMENTARIO` para registrar o estado mental atual do desenvolvedor:
     ```bash
     COMENTARIO="implementar suporte a namespaces" ./dump_tree.sh -g -t
     ```
   - O comentário aparece em destaque no cabeçalho do dump, antes do conteúdo dos arquivos

3. Boas práticas para interação com IA
   - Pergunte de forma específica e incremental
   - Referencie arquivos pelo caminho relativo (ex: "analise dump_tree.sh")
   - Peça verificações de consistência antes de gerar código novo
   - Se o dump for grande, peça análise por partes
   - Use `-o <subpasta>` para gerar dumps menores e mais focados

4. Uso automatizado e em scripts
   - `-y` responde sim a todas as confirmações interativas
   - `-f` força a geração mesmo que a pasta não seja detectada como projeto
   - `-q` ativa o modo silencioso (sem cores, sem interação, sem progresso) — ideal para CI e pipelines
   - Combinação recomendada para automação: `./dump_tree.sh -g -t -q`

5. Limitações conhecidas
   - Dump não inclui binários nem arquivos excluídos (`-d`, `-e`)
   - Estimativa de tokens é aproximada (~3.5 bytes/token, ajustada para PT-BR/UTF-8)
   - Verifique sempre a integridade com `./dump_tree.sh -v`
