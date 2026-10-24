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

O painel apresenta as janelas de 5 horas e semanal quando disponíveis, com data de reset e tempo restante quando a API informa `nextResetTime`. A consulta automática tem intervalo de 15 minutos. A consulta manual respeita intervalo mínimo de 60 segundos e as restrições de respostas HTTP 429.

## Kimi Code

A fonte é `GET https://api.kimi.com/coding/v1/usages`, usada pelo comando de uso do CLI oficial. O monitor usa uma chave do Kimi Code/Coding Plan, guardada no Keychain no serviço `io.github.pcarielo.planmeter.kimi`, conta `quota`.

O resumo `usage` é tratado como semanal conforme o parser oficial do Kimi CLI. As demais janelas são identificadas pela duração retornada. A barra mostra 5h e semanal separadamente; períodos ausentes ficam indisponíveis. Limite zero ou uso ausente não vira saldo zero. A integração não mede saldo financeiro da plataforma Moonshot API nem infere quota mensal não informada.

A coleta automática respeita 15 minutos; a manual, no mínimo 60 segundos. Respostas 429 ampliam a espera. Os prazos são preservados após reiniciar o aplicativo. Erros preservam a última quota, marcada como desatualizada. Pausa e bloqueio cancelam a solicitação pendente.

Não é necessário iniciar conversa com modelo para consultar a quota. O cadastro ocorre no prompt seguro do menu, nunca por chat, argumento, ambiente ou arquivo de configuração. OAuth existente de outros aplicativos fica intacto; esta versão não importa nem renova seus tokens.

Referência de contrato: [consulta de uso do Kimi CLI](https://github.com/MoonshotAI/kimi-cli/blob/main/src/kimi_cli/ui/shell/usage.py).

## Interpretação

Os limites, resets e percentuais dependem da resposta de cada provedor. Um valor antigo, ausente ou indisponível deve ser tratado como falta de informação atual. O histórico local registra observações; ele não é um extrato de cobrança nem uma previsão garantida de disponibilidade.

O monitor não altera planos, compra créditos ou executa resets. Nenhum provedor exige SSH ou uma máquina Linux para esta integração.

## Referências

- [Codex App Server](https://developers.openai.com/codex/app-server/)
- [Statusline do Claude Code](https://code.claude.com/docs/en/statusline)
- [Script de uso publicado pela Z.ai](https://github.com/zai-org/zai-coding-plugins/blob/main/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs)

Essas interfaces podem mudar. Ausência de dados deve ser investigada sem criar sessões de modelo ou copiar credenciais de outros aplicativos.

## Grok: alcance da medição

O PlanMeter consulta o Grok Build oficial autenticado, usando somente `initialize` e `_x.ai/billing`. O percentual corresponde ao saldo de uso incluído retornado em `creditUsagePercent`; o período e a renovação vêm de `currentPeriod`. A consulta não informa uma divisão do percentual por produto.

O cartão usa períodos em português: **Semanal**, **Mensal** e **Uso incluído**, quando o período não é identificado. O nome é Grok; o tipo de crédito aparece separadamente.

- `isUnifiedBillingUser=true`: **Créditos unificados**. A medição cobre a reserva compartilhada dos produtos elegíveis da assinatura. Em The X Subscription, a documentação inclui uso próprio elegível de Grok e Cursor, conforme o plano. Não presumimos os mesmos produtos para toda conta.
- `isUnifiedBillingUser=false`: **Créditos do Grok Build**, incluídos na assinatura. A medição não soma cotas de Chat, Imagine, Voice, Bot, Cursor ou outros produtos.
- Campo ausente: **Tipo de crédito não informado**. Ausência não é tratada como uma confirmação de conta não unificada. Caches antigos sem essa distinção também mostram o estado não informado até a próxima consulta válida.

Créditos adicionais comprados (Extra Usage Credits), saldo pré-pago e consumo adicional cobrado à parte (Pay-as-you-go/Additional Usage) não são somados ao percentual. Eles possuem campos e controles separados no provedor. Contas mostra o alcance resumido, e o botão do Grok abre a explicação da medição junto às instruções de conexão.

A coleta automática usa intervalo de 15 minutos; a manual respeita 60 segundos. O aplicativo procura o executável em `~/.grok/bin`, `~/.local/bin`, `/opt/homebrew/bin` e `/usr/local/bin`. Não lê arquivos de tokens nem cria sessões de conversa.

Fontes oficiais verificadas em 23/10/2026:

- [Rótulos de uso do Grok Build](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/src/views/credit_bar.rs)
- [Contrato de billing do Grok Build](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-shell/src/extensions/billing.rs)
- [Limites do Grok](https://docs.x.ai/grok/faq#how-do-supergroks-weekly-usage-limits-work)
- [Limites de The X Subscription](https://docs.x.ai/x-subscription/usage-limits)
