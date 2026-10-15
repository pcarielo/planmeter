# Provedores e atualização dos dados

## Codex

O PlanMeter usa o Codex CLI oficial já instalado e autenticado. A comunicação é via stdio, com os métodos `account/read` e `account/rateLimits/read`. Não são enviados prompts nem iniciados turnos de modelo para medir uso.

O executável é resolvido pelo `PATH`, por locais comuns ou pelo campo opcional `codexPath` no arquivo `~/Library/Application Support/PlanMeter/config.json`.

Erros de autenticação devem ser resolvidos pelo fluxo oficial do CLI, com participação do usuário. Não copie arquivos de credenciais para o PlanMeter.

## Claude Code

A fonte é o cache local gerado a partir dos dados que o Claude Code fornece à sua statusline. O PlanMeter não usa uma chamada de inferência para produzir esse dado.

O configurador `scripts/configure-claude.py` oferece dois modos:

- `--check`: inspeção sem alterar a configuração.
- `--apply`: configuração com backup e wrapper para preservar a statusline existente.

O helper `scripts/claude-statusline-cache.py` grava o cache usado pelo aplicativo. A atualização depende de atividade no Claude Code e dos campos que sua versão e conta disponibilizam. Atualizar o menu não renova a origem. Ausência de cache ou de campos não significa saldo zero. O helper é passivo e não verifica a identidade da conta; o PlanMeter não infere resets Claude com identidade inventada.

## Z.ai

O PlanMeter consulta um endpoint fixo de quota por HTTPS, com método GET. A chave é fornecida pelo usuário no prompt seguro do aplicativo e armazenada no Keychain do macOS:

| Campo | Valor |
| --- | --- |
| Serviço | `io.github.pcarielo.planmeter.zai` |
| Conta | `quota` |

A chave não deve aparecer em configuração, logs, argumentos de processo ou variáveis de ambiente. O aplicativo não obtém essa chave de credenciais de outros aplicativos.

O menu apresenta as janelas de 5 horas e semanal quando disponíveis. A consulta automática tem intervalo de 15 minutos. A consulta manual respeita intervalo mínimo de 60 segundos e as restrições de respostas HTTP 429.

## Interpretação

Os limites, resets e percentuais dependem da resposta de cada provedor. Um valor antigo, ausente ou indisponível deve ser tratado como falta de informação atual. O histórico local registra observações; ele não é um extrato de cobrança nem uma previsão garantida de disponibilidade.

O monitor não altera planos, compra créditos ou executa resets. Nenhum provedor exige SSH ou uma máquina Linux para esta integração.

## Referências

- [Codex App Server](https://developers.openai.com/codex/app-server/)
- [Statusline do Claude Code](https://code.claude.com/docs/en/statusline)
- [Script de uso publicado pela Z.ai](https://github.com/zai-org/zai-coding-plugins/blob/main/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs)

Essas interfaces podem mudar. Ausência de dados deve ser investigada sem criar sessões de modelo ou copiar credenciais de outros aplicativos.
