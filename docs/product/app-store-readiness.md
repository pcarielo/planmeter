# PlanMeter: caminho para a Mac App Store

Avaliação de 20/10/2026. Proposta de produto e plano técnico, não declaração de conformidade nem submissão à Apple.

## Situação atual

O PlanMeter já consulta quotas, guarda chaves no Keychain e oferece painel, histórico e configurações. Ainda é uma distribuição direta construída por scripts. Não foi encontrado target Xcode para a loja, conjunto de entitlements de sandbox, configuração StoreKit ou manifesto de privacidade. Um Xcode completo será necessário para a etapa de archive e submissão.

A implementação atual de Codex e Grok inicia clientes externos. Claude depende de um arquivo alimentado por outra ferramenta. Z.ai e Kimi usam endpoints de quota cuja existência técnica não comprova autorização comercial para um aplicativo independente. Esses pontos precisam ser resolvidos antes de prometer os cinco provedores na loja.

## Regras que orientam o trabalho

A Apple exige sandbox e empacotamento próprio para a Mac App Store, além de limitar dependências externas e código instalado fora do bundle. Funcionalidades digitais pagas devem seguir a rota de pagamento aplicável à loja; a proposta usa StoreKit. Serviços e marcas de terceiros precisam de permissão compatível com o uso. Uma política de privacidade deve estar acessível no app e na ficha. Aprovação continua sendo decisão da Apple. [App Review Guidelines, 2.4.5, 2.5.2, 3.1.1, 5.1.1 e 5.2](https://developer.apple.com/app-store/review/guidelines/).

## Bloqueios e critérios de saída

| Área | Evidência atual | Trabalho necessário | Critério de saída |
| --- | --- | --- | --- |
| Integrações | Codex/Grok usam processos externos; Claude lê cache externo | Investigar API permitida, OAuth próprio autorizado ou importação escolhida pelo usuário. Não extrair tokens de outros aplicativos | Fluxo útil e reproduzível em instalação limpa, dentro do sandbox e compatível com os termos do provedor |
| Build | Swift compilado por script, assinatura ad hoc padrão | Criar target Xcode separado, bundle ID e capabilities controlados, configuração de distribuição | Archive e validação para distribuição passam com identidade real |
| Credenciais | Keychain legado e autorização manual | Avaliar Keychain de proteção de dados com assinatura estável. Migração explícita, testada e reversível | Persistência após reinício/atualização, sem prompts periódicos ou exportação de segredo |
| Privacidade | Cache local e consultas por cliente oficial | Inventariar tráfego e SDKs, publicar política, preencher declarações e manifesto quando exigido | Documentos correspondem ao comportamento observado, sem afirmação genérica de “não coleta dados” |
| Marca | Favicons obtidos de sites dos provedores | Ícone próprio e revisão de direitos. Preferir texto/ícones próprios onde a permissão não estiver demonstrada | Nenhum ativo de terceiros sem base documentada |
| Qualidade | Testes de fixtures e CI macOS 14/15 | Testar instalação limpa, permissões negadas, rede offline, IPv6, suspensão, múltiplos monitores, VoiceOver e teclado | Fluxos completos sem travamento, dados falsos ou processos duplicados |
| Revisão | Ainda sem cadastro na loja | Modo demonstrativo identificado, suporte, screenshots, notas e contas de revisão quando necessárias | Revisor consegue testar o produto sem credenciais pessoais do desenvolvedor |

O comportamento de CLI não deve ser escondido do revisor. Se uma integração não puder atender a esses critérios, ela fica fora do primeiro release da loja. A edição direta pode continuar existindo, com capacidades e documentação próprias.

## Arquitetura proposta

Manter um núcleo comum de métricas, histórico, preferências e UI. Separar os adaptadores por capacidades explícitas: leitura nativa autorizada, importação de dados escolhida pelo usuário e integração disponível somente na edição direta. O target Store não deve carregar caminhos de instalação de CLIs ou SSH por conveniência.

Primeiro, fazer uma prova de viabilidade com um único provedor dentro de um app sandboxed. A autorização do provedor é um gate próprio. Não vale simular sucesso com fixtures e chamar isso de integração real aprovada. Só depois expandir para os demais provedores.

Para credenciais, usar o armazenamento nativo com acesso mínimo, sem sincronizar chaves por padrão e sem enviá-las a um backend próprio. Qualquer migração deve explicar origem, destino e como reverter. Não alterar o namespace das chaves existentes silenciosamente.

## Experiência de produto

A base deve ser utilizável sem terminal: onboarding curto, Configurações nativas com `⌘,`, estados distintos para sem dados, autorização pendente e dado antigo, exclusão explícita de credenciais e histórico. Abrir ao iniciar sessão deve ser opt-in. O app deve evitar duplicação entre instalações.

Próximas melhorias de produto: navegação completa por teclado e VoiceOver, alertas discretos de saldo baixo, respeito a Reduzir Movimento por padrão em instalações novas, histórico com explicação de lacunas, horários no fuso do usuário, escolha de idioma, diagnóstico sanitizado exportável e testes de longa duração de CPU, memória e número de processos.

## Monetização

Minha recomendação inicial é uma versão gratuita útil e um desbloqueio Pro por compra única. A versão gratuita deve mostrar as quotas disponíveis e permitir configuração segura. O Pro pode agregar histórico prolongado, alertas personalizados, widgets, comparação entre períodos e exportações. Essas funcionalidades ainda não estão implementadas. Segurança, reconexão de conta e indicação de erros não devem virar barreiras pagas.

Assinatura pode fazer sentido depois, se houver valor contínuo claro, como sincronização entre dispositivos, recursos de equipe ou um serviço mantido. Não recomendo mensalidade apenas para exibir os mesmos percentuais. A Apple descreve assinatura como acesso contínuo a conteúdo, serviços ou recursos premium, com gestão e informação clara ao usuário. [Assinaturas na App Store](https://developer.apple.com/app-store/subscriptions/).

Preço deve ser uma hipótese validada com usuários, não uma decisão baseada apenas no custo de desenvolver. Antes de definir valores: conversar com 5 a 10 usuários, medir frequência de uso e quais recursos evitam interrupções, estimar manutenção dos adaptadores e suporte. Comparar compra única com plano anual somente se houver serviço recorrente justificável.

O Small Business Program oferece comissão reduzida de 15% para participantes elegíveis. A elegibilidade e a inscrição precisam ser verificadas; não assumir que já se aplicam. [Programa da Apple](https://developer.apple.com/app-store/small-business-program/).

O código público existente usa MIT, que permite uso comercial mantendo seus termos e avisos. Preservar essa base e decidir separadamente a licença dos novos módulos. Não contar com revogar direitos de quem já recebeu o código. [Licença MIT](https://opensource.org/license/mit).

## Etapas

1. **Base local:** Configurações, preferências persistentes e uma instância principal. Validar sem migrar contas ou habilitar autostart.
2. **Viabilidade Store:** escolher um provedor com acesso permitido, criar target sandboxed e validar autenticação/quotas reais. Documentar o que a edição Store consegue oferecer.
3. **Beta:** identidade de assinatura, TestFlight, onboarding, privacidade, acessibilidade, suporte e modo de demonstração.
4. **Comercialização:** validar a proposta Pro, implementar StoreKit com compra/restauração/expiração quando aplicável e só então configurar produtos e preços.
5. **Submissão:** revisar o binário, as permissões, a ficha e as notas com a conta responsável. Aguardar aprovação humana antes de qualquer envio à loja, contrato ou cobrança.

## Decisões pendentes

- Confirmar no portal a inscrição, a equipe, o Account Holder e a entidade legal antes de escolher o vendedor. E-mail e cartão de cobrança não determinam essa escolha.
- Escolher os provedores do MVP depois da prova técnica e da verificação de termos.
- Aprovar a proposta gratuita + Pro e o conjunto de benefícios antes de implementar pagamentos.
- Definir mercados, suporte e identidade visual própria.

Nada neste plano cria uma conta Apple, compra um programa, cadastra produtos, muda preços ou envia um app para revisão.

## Conferência da conta Apple

Um Apple Account pode participar de mais de uma equipe. O tipo da inscrição e a entidade da equipe determinam o vendedor, não o domínio do e-mail nem o cartão usado na renovação. Antes de separar ou transferir contas, conferir no portal: equipe selecionada, tipo de inscrição, entidade legal, Account Holder e papel do usuário. [Visão geral de conta e equipes](https://developer.apple.com/help/account/basics/about-your-developer-account) e [inscrição individual ou organização](https://developer.apple.com/help/account/membership/program-enrollment/).

A recomendação é escolher a equipe de quem efetivamente será responsável pelo produto e pelas receitas. Se houver uso compartilhado de uma credencial Apple, avaliar convites individuais com permissões por função; não presumir esse compartilhamento apenas por existir um endereço corporativo. Não mudar titular, pagamento, contratos ou associação a equipes durante a inspeção.
