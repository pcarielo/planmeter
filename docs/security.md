# Segurança e armazenamento

## Limites de acesso

O PlanMeter acompanha quotas. Não inicia turnos de modelo, compra créditos, altera planos ou executa resets. Não exige SSH, host remoto ou Linux.

O Codex é consultado pelo CLI oficial já autenticado, por stdio, usando `account/read` e `account/rateLimits/read`. O Claude Code é observado por um cache local alimentado pela statusline. A Z.ai é consultada por GET em um endpoint HTTPS fixo de quota.

## Armazenamento local

Histórico, preferências, configuração e caches ficam em `~/Library/Application Support/PlanMeter/`. O cache do Claude Code é `claude-statusline.json`. O arquivo `config.json` pode conter o campo não secreto `codexPath`, com um caminho absoluto para o CLI.

Esses arquivos podem revelar informações sobre uso e plano. Não os inclua em commits, issues, capturas públicas ou fixtures. Use dados sintéticos ao relatar problemas.

## Chave Z.ai

O usuário cadastra a chave pelo prompt seguro em Configurações → Contas. O armazenamento usa o Keychain do macOS, serviço `io.github.pcarielo.planmeter.zai`, conta `quota`.

A chave não é armazenada em `config.json` nem passada por argumentos, variáveis de ambiente ou logs. O aplicativo não lê credenciais de outros aplicativos para encontrá-la. A remoção é feita em Configurações → Contas.

O acesso depende do Keychain do usuário estar disponível. Quando está bloqueado, a atualização em segundo plano retorna indisponível sem abrir um prompt de desbloqueio. Não há promessa de acesso antes do login. Uma recompilação com assinatura ad hoc pode exigir nova liberação de acesso pelo usuário no Keychain.

A desinstalação preserva a chave. Removê-la é uma decisão separada.

## Frequência e falhas

A consulta automática Z.ai usa intervalo de 15 minutos. A consulta manual tem intervalo mínimo de 60 segundos. Respostas HTTP 429 também restringem tentativas. Falha de acesso, cache antigo e campo ausente não devem ser interpretados como saldo zero.

O cache Claude Code só se renova com atividade do Claude Code. Dados locais não comprovam disponibilidade atual no provedor.

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
