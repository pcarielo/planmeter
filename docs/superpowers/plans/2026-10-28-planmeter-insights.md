# PlanMeter: atualização confiável, registros e insights

**Objetivo:** entregar todos os requisitos da meta de Paulo, sem submissão à App Store.
**Execução:** Sol implementa por etapas; testes isolados e revisão final antes de instalação. O pedido explícito de planejar e seguir até concluir autoriza a execução sem nova aprovação do plano. Publicação Git e operações na conta Apple permanecem separadas.
**Base pre-insights:** main b717ca7532702ea1b326750fa16499ed3f9ba010, versão 1.5.3/build12. Preservar esta referência e criar marco local antes de alterar fontes. Não publicar marco sem autorização.
**Stack:** Swift/AppKit, Foundation, Security, StoreKit, auxiliares Python existentes.

## Requisitos e decisões

- Geral: intervalo de atualização configurável, aplicado imediatamente sem multiplicar timers. Separar intervalo desejado das restrições de cada serviço, Retry-After e consulta já em andamento. Atualizar deve pedir consulta real quando houver integração ativa e explicar qualquer espera.
- Avançado: controles separados para consultas, alterações de configuração e eventos de acesso. Exibir diretórios, botão Visualizar por log, rotação por tamanho e/ou período, retenção padrão mínima de 90 dias ou três meses completos, o que for maior. Rotação não deve apagar registros ainda dentro da retenção. Avisar falha de escrita e pressão de disco, sem apagar silenciosamente registros recentes.
- Registros estruturados com campos permitidos, permissões privadas, sem chave, token, prompt, resposta bruta, ambiente, email ou identidade completa. Eventos de credencial registram apenas provedor, operação e resultado.
- Dashboard: texto Atualizado em. Horário representa a observação efetiva; releitura não fabrica consulta. Fonte passiva identificada quando for o único dado disponível.
- Claude: investigar consulta independente da statusline. Omarchy quattro usa endpoint OAuth de uso; verificar a implementação instalada em Togurux e capacidade do cliente local. Não copiar credenciais de outros aplicativos contrariando as regras do projeto. Priorizar cliente oficial ou fluxo de acesso próprio e explícito; registrar limitação concreta se não houver rota permitida. Nenhum turno de modelo para medir quota.
- Free: até dois planos habilitados/configuráveis, com seleção explícita dos dois ao migrar uma instalação com mais contas. Preservar as credenciais desabilitadas. Guardas no modelo, consulta, Contas, barra e dashboard. Explicar limite e caminho para Pro.
- Pro: todos os planos e insights. Entitlement verificado; modo de simulação Free/Pro exclusivo de build de desenvolvimento, sem desbloqueio arbitrário em distribuição. Preparar compra não consumível e restauração StoreKit; não criar produto remoto nem realizar cobrança. Identificador de produto configurável por build.
- Histórico de amostras: sete dias de observações válidas, separado do histórico de resets. Não inferir retrospectivamente sete dias inexistentes, misturar contas, somar janelas sobrepostas ou tratar reset como consumo negativo. Informar cobertura insuficiente.
- Insights: uma ou duas linhas curtas, em faixa abaixo dos cartões com largura de duas colunas. Pro apenas, geração explícita inicialmente, status ocupado/erro, data e fonte. Projeções numéricas calculadas localmente; modelo recebe apenas resumo agregado e redigido para explicar riscos antes do reset. Nunca enviar chaves, transcrições ou históricos brutos.
- Seleção de modelo/provedor conectado e harness padrão próprio. Permitir caminho absoluto alternativo. Descobrir executáveis via PATH, variáveis de caminho não secretas e diretórios comuns, sem executar configuração shell nem despejar ambiente. Binário encontrado não prova autenticação.
- Adaptadores: Codex, Claude Code, Kimi Code, OpenCode, pi e prime-agent. Validar protocolo/flags pela instalação e documentação antes de implementar. Processo em diretório vazio, prompt por stdin quando suportado, ferramentas desativadas, timeout, saída limitada, cancelamento e proteção dos arquivos dos projetos; estado próprio dos clientes segue as regras documentadas. Só anunciar suporte realmente validado.
- Testes reais de insight autorizados nesta meta, um smoke curto por harness disponível, sem login automático, compras ou uso de API paga alternativa silenciosa. Registrar provedor/modelo/harness e resultado sem conteúdo sensível.

## Execução e evidências

### 1. Diagnóstico e marco
- [x] Confirmar checkout limpo e commit base.
- [x] Ler instruções e documentação pública; identificar integração passiva atual.
- [x] Consultar fonte pública Omarchy: collector Claude usa api.anthropic.com/api/oauth/usage.
- [x] Verificar collector instalado em Togurux e interface Claude local, sem ler segredos.
- [x] Criar marco local pre-insights; registrar versões/capacidades dos seis harnesses.

### 2. Atualização e logs
Arquivos: app/SettingsWindow.swift, app/Core.swift, app/Main.swift; novos app/OperationsSettings.swift e app/AuditLog.swift; testes em app/Tests.swift.
- [x] Testes de migração/defaults, alteração de intervalo em execução, coalescência, cooldown e relógio futuro.
- [x] Implementar política única e controles Geral/Avançado.
- [x] Testes de 90 dias, rotação diária/tamanho/ambos, caminho inseguro, erro de disco e rejeição de campo secreto.
- [x] Instrumentar consultas, configurações e operações de credencial com schemas fechados e visualização por log.

### 3. Claude e semântica de atualização
Arquivos: app/Providers.swift, app/Main.swift, app/QuotaDashboard.swift, app/StatusPresentation.swift; adaptador Claude separado se necessário.
- [x] Reproduzir estado antigo com fixtures e registrar a rota segura escolhida.
- [x] Finalizar a consulta ativa pelo cliente oficial, com cache sanitizado, autenticação indisponível, limitação e cancelamento. O protótipo por token foi removido. Telas antigas, parciais ou em atualização não geram uma observação nova.
- [x] Trocar Recebido em por Atualizado em e preservar observação versus entrega.
- [x] Verificar atualização real pela rota oficial, sem turno de modelo, incluindo nova consulta após os ajustes R3. Fixtures confirmam a preservação do horário quando o cliente mostra dados anteriores.

### 4. Free e Pro
Arquivos novos app/PlanAccess.swift e app/LicenseStore.swift; mudanças em Accounts/Settings/Main; fixtures da política de licença e testes isolados, sem transação Apple.
- [x] Testar zero/um/dois/três planos, migração com cinco e downgrade sem apagar chaves.
- [x] Implementar seleção de dois e guardas compartilhadas no estado/consulta/apresentação.
- [x] Implementar transação verificada, cancelada, pendente, revogada e restaurada; simulação apenas desenvolvimento.
- [x] Validar Free e Pro com identidades isoladas, sem compras reais.

### 5. Amostras e projeção
Novos app/UsageTimeline.swift e testes.
- [x] Testar sete dias completos/parciais, resets, conta trocada, leituras repetidas/fora de ordem, quota ausente, 0%, consumo irregular.
- [x] Persistir somente medidas sanitizadas e calcular ritmo/risco por janela, com cobertura e incerteza explícitas.

### 6. Harnesses e insight
Novos app/InsightRunner.swift, app/HarnessDiscovery.swift e adaptadores pequenos por protocolo; testes de processos fictícios.
- [x] Inspecionar help/documentação de cada instalação e fixar contrato de descoberta/auth/modelos/execução.
- [x] Testar caminhos com espaços, timeout, stdout excessivo, solicitação de ferramenta, falha auth, processo filho e cancelamento.
- [x] Executar smoke real mínimo por harness disponível, sem confundir fixture com suporte real.
- [x] Acrescentar seleção/configuração e faixa de insight, limitando tamanho e frequência. Mudança de seleção cancela resultado antigo.

### 7. Validação e entrega
- [x] Executar scripts/test.sh e doctor.sh, isolamento UI, scanner de segredos e revisão Perry com fontes minimizadas. R4 fechou os seis achados R3; nota final de documentação incorporada.
- [x] Atualizar README, guias de segurança/provedores, changelog e documentação de uso Free/Pro/insights.
- [x] Inspecionar interface com fixtures e capturas sem dados reais.
- [ ] Instalar só depois de validar assinatura/destino e preservar rollback, histórico e autenticação.
- [ ] Verificar uma instância, refresh real, logs, seleção Free/Pro e insight no aplicativo instalado.
- [ ] Auditar cada requisito acima antes de concluir a meta. Publicação App Store fora do escopo; Git requer autorização específica.

## Fontes verificadas
- https://raw.githubusercontent.com/omacom/omarchy/quattro/bin/omarchy-agent-usage-claude
- https://raw.githubusercontent.com/omacom/omarchy/quattro/shell/plugins/agents/README.md
- https://developer.apple.com/documentation/storekit/getting-started-with-in-app-purchases-using-storekit-views

## Riscos que precisam de prova
1. Uma chegada de cache recente não prova consulta ao provedor.
2. Um executável encontrado não prova conexão ou ausência de ferramentas.
3. Rotação por tamanho não pode eliminar silenciosamente os 90 dias prometidos.
4. O downgrade não pode apagar autenticação nem continuar consultando planos desabilitados.
5. Sete dias incompletos não podem gerar previsão apresentada como certeza.


## Estado da implementação

Candidata 1.6.0 em validação local. Os detalhes operacionais e os resultados de cada execução ficam no registro privado da instalação. A conclusão depende da revisão final, da validação do aplicativo instalado e dos consentimentos de acesso. Publicação na App Store permanece fora do escopo.
