# Insights e edição Pro

O insight interpreta o ritmo de consumo dos planos ativos e aponta uma implicação prática, como aceleração, risco de esgotamento ou margem estimada até a renovação. Não é uma repetição dos cartões. Ele aparece abaixo dos cartões, ocupa a largura das duas colunas e mostra a data, o harness e o modelo usados.

A geração é uma ação separada da atualização de quotas. **Gerar insight consome o modelo escolhido e pode gastar a quota da assinatura.** Atualizar quotas não inicia uma conversa.

## Free e Pro

A edição Free permite selecionar até dois planos em **Configurações → Contas**. Só os planos selecionados são consultados e exibidos. Se você trocar a seleção, as chaves e os dados anteriores continuam guardados.

Pro libera todos os planos e os insights. O aplicativo usa StoreKit para verificar uma compra não consumível, sem assinatura recorrente. A compra e a restauração dependem da configuração do produto na distribuição Apple. Esse modelo de desbloqueio usa [compras não consumíveis do StoreKit](https://developer.apple.com/documentation/storekit/getting-started-with-in-app-purchases-using-storekit-views). Quando o produto não está disponível, o aplicativo informa isso e não tenta cobrar.

Na migração, até dois provedores conhecidos são preservados. Se houver mais, Contas abre para você escolher. Ao voltar de Pro para Free com mais de dois selecionados, escolha quais dois manter ativos. Nenhuma chave é apagada.

## Configurar um insight

1. Abra **Configurações → Insights**.
2. Escolha o provedor que fornecerá o modelo. Essa escolha é independente dos planos selecionados para monitoramento: você pode, por exemplo, usar Kimi pelo pi para analisar Codex e Grok. Um cliente já escolhido é preservado se for compatível; caso contrário, o cliente próprio é sugerido.
3. Use **Buscar modelos no harness** ou informe o identificador do modelo. A busca filtra pelo provedor escolhido. Se o pi estiver configurado para Kimi Coding e o provedor selecionado for Codex, o catálogo pode ficar vazio; escolha Kimi Code para ver os modelos dessa rota.
4. Confira o executável encontrado. Para usar outra instalação do mesmo harness, preencha o caminho alternativo.
5. Aplique as opções e use **Verificar conexão**.
6. No painel de disponibilidade, clique em **Gerar insight**.

Os caminhos são procurados no `PATH`, em diretórios comuns de instalação e nas variáveis opcionais `PLANMETER_CODEX_PATH`, `PLANMETER_CLAUDE_PATH`, `PLANMETER_KIMI_PATH`, `PLANMETER_OPENCODE_PATH`, `PLANMETER_PI_PATH` e `PLANMETER_PRIME_AGENT_PATH`. Essas variáveis contêm somente caminhos. Não coloque credenciais nelas.

A lista mostra todos os clientes suportados. Os incompatíveis com o provedor selecionado aparecem desabilitados, com indicação dos provedores que aceitam. Um catálogo encontrado não comprova autenticação; use Verificar conexão. Alterações no modelo ou caminho precisam ser aplicadas.

O programa não executa o shell para interpretar um caminho. Um caminho alternativo inválido produz erro, sem trocar silenciosamente para outra instalação.

## Harnesses

| Harness | Preparação e limites |
| --- | --- |
| Codex | Login ChatGPT no CLI oficial. Catálogo por `model/list`. API key não substitui a assinatura. A execução usa perfil mínimo, sem escrita ou rede de ferramentas, e desativa comandos, hooks, apps, agentes, imagens e busca web. |
| Claude Code | Login da assinatura no CLI. Ferramentas, hooks e MCP ficam desativados nessa execução. A sessão do insight não é persistida pelo modo usado. |
| Kimi Code | Usa a configuração OAuth gerenciada do Kimi Code. O agente temporário tem lista vazia de ferramentas e subagentes. O cliente pode manter seus próprios registros de sessão. |
| OpenCode | Usa o provedor específico do Coding Plan. A execução ignora plugins externos, isola a configuração e nega ferramentas. Compartilhamento automático fica desativado. O cliente pode manter seu histórico local. |
| pi | Ferramentas, extensões, MCP, skills e persistência de sessão ficam desativados. Codex exige OAuth; uma chave de API avulsa é recusada nessa rota. Assinaturas Claude usam somente o cliente oficial. |
| Prime Agent | Usa o binário nativo. Como o harness mantém uma ferramenta Python interna, o PlanMeter aplica contenção adicional do macOS: outros executáveis são bloqueados e a escrita fica limitada ao diretório temporário e ao estado próprio do Prime. A geração usa um canal CONNECT temporário em loopback, restrito aos hosts do Coding Plan e à porta 443. Destinos privados são recusados, e o processo não tem conexão TCP direta com outros destinos. Essa proteção não isola leitura de arquivos, Mach, XPC ou AppleEvents; ela não constitui um sandbox completo. O canal preserva o TLS entre o cliente e o provedor. Esta integração requer Node.js 18 ou posterior. O PlanMeter procura o Node no PATH, Homebrew, Volta, nvm e mise. `PLANMETER_NODE_PATH` permite indicar um executável específico. Se a contenção falhar, a geração não prossegue. |

O insight usa a conta conectada no harness, que pode ser diferente da conta monitorada por uma chave no PlanMeter. Confira essa conta no cliente escolhido. No Prime, as rotas oferecidas são Kimi Coding e Z.ai Coding Plan; Claude e Codex usam os outros clientes compatíveis.

Um catálogo de modelos não comprova que a credencial funciona. Nos clientes que só informam configuração local, a interface deixa claro que a conexão será confirmada na geração. Erros não acionam outro provedor ou uma API paga como alternativa.

Grok pode participar da análise de métricas, mas ainda não é oferecido como gerador de insights nesta integração. O cadastro de um harness não muda o alcance da quota medida por cada provedor.

## Dados usados e limites da previsão

O PlanMeter mantém observações dos últimos sete dias. Medidas que mudam são guardadas; valores repetidos recebem uma amostra a cada 30 minutos. As gravações são agrupadas e executadas fora da interface. Ao iniciar, o aplicativo também recupera leituras com data e saldo que já estavam nos registros dos detectores, sem duplicá-las. O histórico de períodos e renovações entra como contexto separado; uma renovação, sozinha, não vira uma amostra de consumo.

A projeção compara medidas da mesma janela e da mesma conta identificada. Para Z.ai e Kimi, também pode usar a continuidade da configuração de chave gerenciada pelo aplicativo. A continuidade usa um resumo SHA-256 da chave efetivamente utilizada na consulta (verificador, não cifra), guardado só em arquivos privados, sem guardar seu valor no histórico. Trocar a chave separa as sequências. O marcador não é enviado ao modelo. Essa continuidade local não é apresentada como uma identidade de conta fornecida pelo serviço.

Um reset não é consumo negativo. Intervalos longos sem observações não são tratados como cobertura contínua. O cálculo precisa de pelo menos uma hora coberta e três observações comparáveis. O ritmo recente usa as últimas seis horas; a comparação usa a mesma faixa horária em pelo menos dois dias anteriores, sem sobreposição entre os grupos. Cada grupo precisa de pelo menos uma hora coberta e dois intervalos válidos entre leituras. Para prever até seis horas adiante, usa-se o ritmo recente. Para horizontes maiores, usa-se a variação de saldo por hora de relógio do mesmo período, incluindo pausas, em blocos de dias completos terminando na leitura atual. O cálculo procura uma leitura do mesmo horário em um dia anterior, aceitando até uma hora de diferença para trás. Se não a encontrar, tenta um bloco menor. Se o período atual ainda for curto, podem ser usados períodos anteriores da mesma conta ou configuração de chave, também com dias completos registrados, sem atravessar resets no cálculo. Um pico do expediente não é extrapolado como atividade contínua por vários dias. Mudanças de ritmo são destacadas a partir de 25%, com diferença mínima de 0,1 ponto percentual por hora. Margem projetada abaixo de 10% recebe prioridade sobre uma margem maior. Quando não há sinal analítico suficiente, o aplicativo informa esse estado e não chama o modelo apenas para repetir saldo e calendário. O tom deve ser cordial, direto e proporcional aos dados.

O modelo recebe somente sinais analíticos calculados localmente, com prioridade e fatos que sustentam cada interpretação. Isso inclui risco de esgotamento antes da renovação, mudança de ritmo e margem projetada se o padrão continuar. O envio não inclui a tabela dos cartões para ser recontada, nem chaves, tokens, emails, identificadores completos de conta, transcrições ou arquivos de projetos. O modelo explica os sinais em uma ou duas linhas, sem recalcular os dados ou tratar uma projeção como garantia.

Quando as métricas mudam, uma janela renova ou a resposta completa uma hora, o painel informa que é preciso gerar outro insight. A estimativa não garante disponibilidade futura.

## Testar Free e Pro sem compra

Um build de desenvolvimento pode incluir a simulação local:

```sh
PLANMETER_DEVELOPMENT=1 ./scripts/test.sh
PLANMETER_DEVELOPMENT=1 ./scripts/build.sh
```

Nesse build, **Geral → Licença → Simular Pro** alterna os recursos sem realizar compra. A simulação não é uma licença Apple e não existe no build normal. Compilar não instala nem substitui a versão em uso.

Os testes de política e interface usam fixtures. Eles não comprovam uma transação real na App Store. Publicação, cadastro de produto, preço e validação de compra Apple pertencem a uma etapa posterior.

## Validação dos adaptadores

Os seis harnesses foram exercitados no macOS com dados fictícios. A verificação dos adaptadores cobre execução e formato. No fluxo analítico, o resultado esperado é uma interpretação curta dos sinais calculados, e não uma lista de saldos e datas. O cenário sintético de aceleração e esgotamento foi conferido no Codex; as guardas e os cálculos são testados localmente para todos os adaptadores. Esses testes comprovam a execução nas instalações verificadas; não representam uma previsão sobre sete dias de uso real nem garantem compatibilidade com versões futuras.

As versões verificadas foram Codex CLI 0.162.0, Claude Code 2.1.312, Kimi Code 2.3.3, OpenCode 1.19.0, pi 1.4.0 e Prime Agent 0.10.1. O cálculo de risco e o tratamento de resets são testados separadamente com sete dias de dados sintéticos.


## Atualizar um provedor

Passe o ponteiro sobre um cartão para acender a borda e mostrar a ação acima dele. Clique em qualquer parte do cartão para consultar somente aquele provedor. O clique mantém o painel aberto; os demais cartões continuam disponíveis. Durante a consulta, o cartão mostra “Atualizando…”. Se o provedor impuser um intervalo mínimo, aparece o tempo restante. A consulta passiva do Claude é identificada como releitura local.

O botão geral continua atualizando todos os planos selecionados. Consultas automáticas dos outros provedores mantêm sua própria programação.
