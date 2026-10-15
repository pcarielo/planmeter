# Ícones dos provedores

O repositório não inclui os favicons dos provedores. O build padrão baixa os arquivos públicos indicados em `scripts/provider-icons.json`, valida seus hashes e mantém uma cópia local em `build/provider-icons/`.

As marcas pertencem aos titulares. Não há afiliação ou endosso. A licença MIT deste projeto não licencia esses recursos. Não publique binários com recursos de terceiros sem verificar os termos aplicáveis.

Para gerar somente os ícones próprios de iniciais, sem download, use `PLANMETER_ICON_MODE=initials ./scripts/build.sh`. Os testes usam essa opção.
