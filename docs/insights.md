# Insights e edição Pro

O insight resume o ritmo de consumo dos planos ativos. Ele aparece abaixo dos cartões, ocupa a largura das duas colunas e mostra a data, o harness e o modelo usados.

A geração é uma ação separada da atualização de quotas. **Gerar insight consome o modelo escolhido e pode gastar a quota da assinatura.** Atualizar quotas não inicia uma conversa.

## Free e Pro

A edição Free permite selecionar até dois planos em **Configurações → Contas**. Só os planos selecionados são consultados e exibidos. Se você trocar a seleção, as chaves e os dados anteriores continuam guardados.

Pro libera todos os planos e os insights. O aplicativo usa StoreKit para verificar uma compra não consumível, sem assinatura recorrente. A compra e a restauração dependem da configuração do produto na distribuição Apple. Esse modelo de desbloqueio usa [compras não consumíveis do StoreKit](https://developer.apple.com/documentation/storekit/getting-started-with-in-app-purchases-using-storekit-views). Quando o produto não está disponível, o aplicativo informa isso e não tenta cobrar.

Na migração, até dois provedores conhecidos são preservados. Se houver mais, Contas abre para você escolher. Ao voltar de Pro para Free com mais de dois selecionados, escolha quais dois manter ativos. Nenhuma chave é apagada.

## Configurar um insight

1. Abra **Configurações → Insights**.
2. Escolha o plano que fornecerá o modelo. O harness próprio é sugerido quando existe uma integração correspondente.
3. Use **Buscar modelos no harness** ou informe o identificador do modelo.
4. Confira o executável encontrado. Para usar outra instalação do mesmo harness, preencha o caminho alternativo.
5. Aplique as opções e use **Verificar conexão**.
6. No painel de disponibilidade, clique em **Gerar insight**.

Os caminhos são procurados no `PATH`, em diretórios comuns de instalação e nas variáveis opcionais `PLANMETER_CODEX_PATH`, `PLANMETER_CLAUDE_PATH`, `PLANMETER_KIMI_PATH`, `PLANMETER_OPENCODE_PATH`, `PLANMETER_PI_PATH` e `PLANMETER_PRIME_AGENT_PATH`. Essas variáveis contêm somente caminhos. Não coloque credenciais nelas.

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

Grok pode participar do resumo de métricas, mas ainda não é oferecido como gerador de insights nesta integração. O cadastro de um harness não muda o alcance da quota medida por cada provedor.

## Dados usados e limites da previsão

O PlanMeter mantém observações dos últimos sete dias. Medidas que mudam são guardadas; valores repetidos recebem uma amostra a cada 30 minutos. As gravações são agrupadas e executadas fora da interface. Ao iniciar, o aplicativo também recupera leituras com data e saldo que já estavam nos registros dos detectores, sem duplicá-las. O histórico de períodos e renovações entra como contexto separado; uma renovação, sozinha, não vira uma amostra de consumo.

A projeção compara medidas da mesma janela e da mesma conta identificada. Para Z.ai e Kimi, também pode usar a continuidade da configuração de chave gerenciada pelo aplicativo. A continuidade usa um resumo SHA-256 da chave efetivamente utilizada na consulta (verificador, não cifra), guardado só em arquivos privados, sem guardar seu valor no histórico. Trocar a chave separa as sequências. O marcador não é enviado ao modelo. Essa continuidade local não é apresentada como uma identidade de conta fornecida pelo serviço.

Um reset não é consumo negativo. Intervalos longos sem observações não são tratados como cobertura contínua. O cálculo precisa de pelo menos uma hora coberta e três observações comparáveis. Quando não há base para projetar o ritmo, o insight aproveita o saldo, o calendário e as mudanças efetivamente observadas. Ele não inventa uma previsão nem repete diagnósticos negativos para cada provedor. O tom deve ser cordial, direto e proporcional aos dados.

O modelo recebe **um resumo agregado de todos os planos ativos**, inclusive de serviços diferentes do provedor escolhido para gerar o insight, além do horário atual e do fuso horário local. O PlanMeter não inclui no prompt chaves, tokens, emails, identificadores completos de conta, transcrições ou arquivos de projetos. Os clientes podem acrescentar suas próprias instruções e metadados de execução. Contadores de períodos representam o histórico local, sem somar registros de outras contas ou sem identificação aos de uma conta identificada. O ritmo e a estimativa de esgotamento são calculados localmente; o modelo os explica em uma ou duas linhas.

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

Os seis harnesses foram exercitados no macOS com dados fictícios. O resultado esperado é uma resposta curta com saldos, observações históricas e próximos prazos, conforme os dados fornecidos. Não se exige que o texto repita diagnósticos de falta de dados. Esses testes comprovam a execução nas instalações verificadas; não representam uma previsão sobre sete dias de uso real nem garantem compatibilidade com versões futuras.

As versões verificadas foram Codex CLI 0.162.0, Claude Code 2.1.312, Kimi Code 2.3.3, OpenCode 1.19.0, pi 1.4.0 e Prime Agent 0.10.1. O cálculo de risco e o tratamento de resets são testados separadamente com sete dias de dados sintéticos.
