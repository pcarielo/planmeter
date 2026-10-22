# Alterações

## 1.4.0 - 2026-10-22

- Configurações nativas com Geral, Contas, Aparência, Avisos e Sobre, acessíveis por `⌘,`.
- Preferências de tema, tamanho e prazo de fechamento do painel persistidas localmente.
- Início automático por API nativa, somente por escolha do usuário, com proteção contra builds temporários e configuração legada duplicada.
- Aviso ao detectar outra instalação do monitor.
- Percentuais inteiros na barra, no painel e no histórico.
- Configurações abrem sem fechar o painel; fechar o painel desativa a fixação.
- Kimi fica oculto até uma consulta autenticada nesta execução e quando o acesso à chave falha.
- Avisos de reset confirmados permanecem até o reconhecimento e aceitam clique direto.
- Renovação programada pode ser detectada após suspensão, reinício ou atraso, com comparação da mesma conta e janela.

## 1.3.1 - 2026-10-19

- Leituras automáticas do Keychain não abrem diálogos de autenticação.
- Autorização explícita pelo painel Acessos e reutilização da chave em memória durante a execução.
- Opção de usar identidade de assinatura configurada no Mac para manter a confiança entre versões.

## 1.3.0 - 2026-10-19

- Provedores sem métricas ficam ocultos também na barra. Saldo zero continua visível.
- Botão Acessos com cadastro seguro de chaves e guias de autenticação dos clientes oficiais.
- README com capturas do painel completo e do aviso de reset, usando dados fictícios.
- Cadastro Z.ai aceita colagem pelo teclado e mostra falhas no próprio fluxo.

## 1.2.0 - 2026-10-19

- Painel flutuante com cartões apenas dos provedores que têm métricas, atualização manual, fixação e tamanhos 1×, 1,25× e 1,5×.
- Janela fixada pode ser movida pela faixa superior. O menu de contexto mantém apenas ações e configurações.
- Grok Unified pelo cliente oficial Grok Build, com quota compartilhada, favicon e próximo reset.
- Data de reset e contagem regressiva da Z.ai, quando fornecidas pela API.
- Colagem no campo seguro Kimi e avisos visíveis para cadastro vazio ou consulta com falha.
- Painel disponível para captura de tela e sem fechamento por clique externo.

## 1.1.0 - 2026-10-19

- Kimi Code na barra de menus, com ícone e saldos de 5h e semanal separados.
- Cadastro e remoção da chave Kimi pelo Keychain do macOS, sem alterar o OAuth de outros aplicativos.
- Consulta automática a cada 15 minutos, intervalo manual de 60 segundos e preservação da última quota em caso de erro.
