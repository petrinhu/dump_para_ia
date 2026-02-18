# Como Contribuir

Obrigado pelo interesse em contribuir com `dump_tree.sh`!

## Reportar bugs

Abra uma issue e descreva:

- Versão do script (veja o CHANGELOG)
- Comando usado
- Saída ou mensagem de erro
- Distro e versão do Bash (`bash --version`)
- Passos para reproduzir

## Propor melhorias

1. Abra uma issue descrevendo a ideia e o problema que ela resolve
2. Aguarde feedback do mantenedor antes de implementar — isso evita trabalho desperdiçado
3. Se a ideia for aceita, crie um pull request seguindo as diretrizes abaixo

**Uma melhoria tende a ser aceita quando:**

- Resolve um problema real sem adicionar dependências novas
- É consistente com a filosofia KISS do projeto (simples, direto, portável)
- Funciona corretamente em Bash 4+ no Fedora (plataforma principal de desenvolvimento)
- Não quebra nenhuma das flags ou comportamentos existentes

## Pull Requests

- Use branch separada (ex: `feature/suporte-rust`, `fix/estimativa-tokens`)
- Commits atômicos com mensagens claras no imperativo (ex: `Adiciona suporte a .kt`)
- Teste com `./dump_tree.sh -g -n` e `./dump_tree.sh -g -q` antes de abrir o PR
- Atualize o `README.md` se a mudança afetar opções, comportamento ou exemplos
- Registre a mudança em `CHANGELOG.md` na seção `[Unreleased]`

## Ambiente de desenvolvimento

O projeto é desenvolvido e testado primariamente no **Fedora Linux** com **Bash 4+**.
Contribuições testadas em outras distros são bem-vindas, mas o critério de aceitação é o comportamento no Fedora.

Para verificar a sintaxe sem executar:

```bash
bash -n dump_tree.sh
```

Obrigado por contribuir!
