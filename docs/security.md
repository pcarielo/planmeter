# Segurança e armazenamento

## Limites de acesso

O PlanMeter acompanha quotas. Medir quotas não inicia turnos de modelo, compra créditos, altera planos ou executa resets. A geração opcional de insights no Pro usa explicitamente o modelo escolhido pelo usuário e pode consumir sua quota. Não exige SSH, host remoto ou Linux.

O Codex é consultado pelo CLI oficial já autenticado, por stdio, usando `account/read` e `account/rateLimits/read`. O Claude Code pode ser consultado ativamente após consentimento ou observado pela statusline passiva. A Z.ai é consultada por GET em um endpoint HTTPS fixo de quota.

## Armazenamento local

Histórico, preferências, configuração e caches ficam em `~/Library/Application Support/PlanMeter/`. O cache do Claude Code é `claude-statusline.json`. O arquivo `config.json` pode conter o campo não secreto `codexPath`, com um caminho absoluto para o CLI.

Esses arquivos podem revelar informações sobre uso e plano. Não os inclua em commits, issues, capturas públicas ou fixtures. Use dados sintéticos ao relatar problemas.

## Chave Z.ai

O usuário cadastra a chave pelo prompt seguro em Configurações → Contas. O armazenamento usa o Keychain do macOS, serviço `io.github.pcarielo.planmeter.zai`, conta `quota`.

A chave não é armazenada em `config.json` nem passada por argumentos, variáveis de ambiente ou logs. O aplicativo não lê credenciais de outros aplicativos para encontrá-la. A remoção é feita em Configurações → Contas.

O acesso depende do Keychain do usuário estar disponível. Quando está bloqueado, a atualização em segundo plano retorna indisponível sem abrir um prompt de desbloqueio. Não há promessa de acesso antes do login. Uma recompilação com assinatura ad hoc pode exigir nova liberação de acesso pelo usuário no Keychain.

A desinstalação preserva a chave. Removê-la é uma decisão separada.

## Frequência e falhas

A consulta automática segue o intervalo configurado, com padrão de 15 minutos. A consulta manual tem intervalo mínimo de 60 segundos. Respostas HTTP 429 também restringem tentativas. Falha de acesso, cache antigo e campo ausente não devem ser interpretados como saldo zero.

No modo passivo, o cache Claude Code só se renova com atividade do cliente. Dados locais não comprovam disponibilidade atual no provedor.

## Distribuição

O projeto ainda não oferece assinatura Developer ID ou notarização. Builds locais usam assinatura ad hoc. Não desative o Gatekeeper ou remova atributos de quarentena para contornar alertas. Registre a origem do build e a mensagem exibida para investigar o problema.

Para comunicação de vulnerabilidades, consulte [SECURITY.md](../SECURITY.md).

## Kimi Code

A chave do Kimi Code fica no Keychain em item separado do Z.ai. O cliente faz somente GET de quota no host fixo api.kimi.com, não segue redirecionamentos e limita a resposta. Não lê tokens OAuth ou arquivos de autenticação do Kimi CLI. Testes usam credenciais fictícias e transportes injetados, sem rede ou Keychain reais.

## Grok

O PlanMeter inicia o cliente oficial Grok Build em um diretório temporário vazio para consultar a assinatura via ACP. Não lê o arquivo de autenticação e não envia prompts. Solicitações de ferramentas recebidas pelo protocolo são recusadas. O cache guarda apenas quota, período, reset e indicação de assinatura unificada; dados financeiros e identificação pessoal da resposta são descartados.

## Autorização do Keychain sem interrupções periódicas

As leituras automáticas não podem abrir diálogos. O aplicativo bloqueia a interação tanto no contexto de autenticação quanto na API do Keychain baseado em arquivos do macOS. As operações são serializadas, incluindo gravação e remoção, para que uma consulta em segundo plano não altere a política de uma ação manual.

Quando o sistema exige autorização, o usuário escolhe **Configurações → Contas → Autorizar acesso**. Somente essa ação, o cadastro ou a remoção podem solicitar interação. Uma leitura autorizada pode ser reutilizada em memória durante a execução. A chave persistente continua no Keychain; não é exportada para configuração, cache, ambiente ou logs. Remover ou substituir a chave também atualiza essa cópia em memória.

Builds ad hoc têm identidade vinculada ao conteúdo do executável. Uma atualização pode exigir nova autorização, ainda que o nome do aplicativo seja igual. Para manter a identidade entre versões, o build aceita `PLANMETER_SIGN_IDENTITY` com uma identidade de assinatura válida já configurada no Mac. Isso não cria certificados, não concede confiança a todos os aplicativos e não transforma o build em uma distribuição notarizada. A distribuição padrão continua ad hoc.

Se o Keychain estiver bloqueado ou negar acesso, o monitor preserva a última quota e informa a necessidade de uma ação manual. Ele não pede a senha a cada coleta.

## Histórico de renovações e exportação

`renewal-history.json` guarda os períodos conhecidos, horários de observação e origem das datas no diretório privado do aplicativo. A referência de conta, quando disponível, é o identificador pseudônimo já usado pelo monitor; credenciais e tokens não entram nesse histórico. Não há envio do histórico a um servidor do PlanMeter.

A exportação CSV acontece somente quando o usuário aciona o botão e escolhe o destino. O arquivo contém os registros completos, com datas em ISO 8601, evidência e referência abreviada da conta. Campos de texto são escapados e protegidos contra interpretação como fórmulas em planilhas. Dados de uso reais e CSVs exportados não devem entrar no repositório.

Se o arquivo de histórico não puder ser decodificado, a versão anterior é preservada em um arquivo de recuperação e o aplicativo informa a falha. Se não puder preservar o original, a gravação fica suspensa para evitar sobrescrevê-lo.

## Consulta ativa Claude

O PlanMeter abre o binário oficial e lê a tela `/usage` sem acessar o item do Claude no Keychain. Ferramentas, MCP e hooks ficam desativados nessa consulta. O terminal é limitado em tempo e volume de saída; seu conteúdo não é gravado nos logs do aplicativo. O cache guarda apenas quotas e horários.

A pasta de consulta é exclusiva do PlanMeter. A coleta automática não aceita diálogos de confiança ou login. O cliente oficial pode manter seu próprio estado local; o PlanMeter não remove sessões de outros projetos. A alternativa passiva continua disponível.

## Insights e licenças

Os adaptadores usam o cliente escolhido e sua autenticação existente. O PlanMeter não extrai chaves dos harnesses. O provedor do insight recebe um agregado das métricas de todos os planos ativos; o usuário deve considerar esse compartilhamento ao escolher o gerador.

O runner limita tempo, entrada e saída, encerra o grupo de processos e não encaminha variáveis incidentais de API key. Ferramentas são desativadas ou negadas conforme o contrato do cliente. O Prime exige contenção externa adicional e um gateway CONNECT efêmero que aceita apenas os hosts do Coding Plan, recusa endereços privados e preserva o TLS. Essa contenção restringe criação de processos, escrita e conexões TCP, mas não isola leitura de arquivos, Mach, XPC ou AppleEvents. Não há fallback para execução sem essa proteção. O Kimi e o OpenCode podem manter seus próprios registros locais do insight.

StoreKit concede Pro somente a uma transação verificada do produto esperado. A preferência de planos não é prova de licença. A simulação Free/Pro é compilada apenas no modo de desenvolvimento. Esses controles não são uma promessa de proteção contra alterações no código-fonte distribuído sob MIT.

Veja [insights](insights.md) e [logs](logs.md) para alcance, retenção e limites. A distribuição ainda não foi submetida à App Store. A execução de CLIs externos e a contenção do Prime exigem avaliação específica para essa distribuição futura.

## Compatibilidade com a autenticação Claude

A [política de autenticação da Anthropic](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use) restringe a coleta e intermediação de tokens de sessão do Claude.ai por desenvolvedores de terceiros. O consentimento local do usuário não substitui as condições do provedor.

O protótipo que lia o token no Keychain foi removido. A consulta ativa usa a tela de uso do binário oficial, sem extrair a credencial. Essa rota foi validada em consulta real com Claude Code 2.1.312, sem extrair credenciais ou enviar um pedido ao modelo.

Para gerar insights com uma assinatura Claude, o PlanMeter oferece somente o Claude Code oficial, sem modificar o binário. As rotas Claude por pi e OpenCode foram retiradas. Os demais provedores continuam sujeitos aos seus próprios contratos e às rotas documentadas.
