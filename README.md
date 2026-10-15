# PlanMeter

Quotas de Codex, Claude Code e Z.ai na barra de menus do macOS.

O PlanMeter é um aplicativo Swift/AppKit que mostra o saldo disponível, as janelas de uso e as previsões de reset fornecidas por cada serviço. Inclui histórico local e confete para celebrar resets. Não inicia conversas com modelos para medir quotas.

![Exemplo com ícones de iniciais e valores fictícios](docs/images/statusbar.png)

## Como funciona

| Provedor | Fonte | Preparação |
| --- | --- | --- |
| Codex | `account/read` e `account/rateLimits/read` do Codex CLI oficial, via stdio | Instalar o CLI e entrar na conta pelo fluxo oficial |
| Claude Code | Cache local alimentado pela statusline do Claude Code | Configurar o helper incluído neste repositório |
| Z.ai | Endpoint HTTPS de quota | Cadastrar sua chave no menu do aplicativo |

O build padrão obtém os favicons dos sites dos provedores e os guarda somente no build local. Para usar ícones próprios sem esse download, execute `PLANMETER_ICON_MODE=initials ./scripts/install.sh`. Os ícones identificam os provedores na barra de menus. O menu mostra seus nomes e o detalhe das quotas, incluindo as janelas de 5 horas e semanal da Z.ai. A disponibilidade de cada informação depende do que o provedor retorna.

O cache do Claude Code se renova quando há atividade no Claude Code. Atualizar o PlanMeter não força uma nova consulta de quota desse provedor.

## Instalação a partir do código

Requisitos: macOS 13 ou posterior, Xcode Command Line Tools, Python 3 e Git. A validação real realizada até agora cobre Apple Silicon com macOS 26. Outras versões e Macs Intel ainda precisam de validação.

```sh
git clone https://github.com/pcarielo/planmeter.git
cd planmeter
./scripts/test.sh
./scripts/install.sh
```

A instalação padrão usa `~/Applications/PlanMeter.app` e não ativa início automático. Para ativá-lo, use `./scripts/install.sh --login` ou consulte o [guia de instalação](docs/getting-started.md).

O aplicativo ainda não tem assinatura Developer ID nem notarização. O build local usa assinatura ad hoc. Não há recomendação de desativar o Gatekeeper ou remover atributos de quarentena.

## Configuração dos provedores

- **Codex:** use uma instalação oficial do Codex CLI já autenticada. O aplicativo procura o executável no `PATH` e em locais comuns. Um caminho explícito pode ser definido em `codexPath` no arquivo de configuração local.
- **Claude Code:** execute `python3 scripts/configure-claude.py --check` para inspecionar a configuração. Depois, `python3 scripts/configure-claude.py --apply` configura o helper com backup e preserva a statusline existente por meio de um wrapper.
- **Z.ai:** abra o menu do aplicativo e escolha a opção de configurar a chave. O prompt seguro grava a chave no Keychain do macOS.

Veja os [primeiros passos](docs/getting-started.md), os [detalhes de cada provedor](docs/providers.md) e as [instruções para um agente ajudar na instalação](docs/agent-setup.md).

## Dados e segurança

O estado local fica em `~/Library/Application Support/PlanMeter/`. A chave Z.ai fica no Keychain, separada da configuração. O aplicativo não lê credenciais de outros aplicativos para obter essa chave.

As consultas Z.ai automáticas têm intervalo de 15 minutos. A atualização manual respeita um intervalo mínimo de 60 segundos e o tratamento de respostas HTTP 429. Monitorar quotas não autoriza criar sessões de modelo, comprar créditos, alterar planos ou executar resets.

A [documentação de segurança](docs/security.md) descreve o armazenamento e os limites de acesso. Para relatar uma vulnerabilidade, consulte [SECURITY.md](SECURITY.md).

## Desenvolvimento e licença

Os testes usam fixtures: `./scripts/test.sh`. Consulte [CONTRIBUTING.md](CONTRIBUTING.md) antes de propor mudanças.

Código próprio sob [licença MIT](LICENSE). Nomes, logos e ícones de provedores pertencem aos respectivos titulares e não recebem licença MIT por estarem no repositório. Consulte [THIRD_PARTY.md](THIRD_PARTY.md). O PlanMeter é um projeto independente, sem afiliação ou endosso dos provedores.
