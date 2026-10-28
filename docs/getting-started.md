# Primeiros passos

## Preparar o Mac

Use macOS 13 ou posterior com Xcode Command Line Tools. Se as ferramentas ainda não estiverem instaladas, inicie o instalador da Apple:

```sh
xcode-select --install
```

Build e testes com fixtures passaram em Apple Silicon no macOS 14 e 15 pelo GitHub Actions, e no macOS 26 localmente. macOS 13 e Macs Intel ainda não foram validados em execução.

## Testar, instalar e abrir

Na raiz do repositório:

```sh
./scripts/test.sh
./scripts/install.sh
```

O destino padrão é `~/Applications/PlanMeter.app`. Compilar e instalar são ações distintas. Use o aplicativo instalado para o uso diário.

O build local tem assinatura ad hoc. Não há assinatura Developer ID ou notarização nesta versão. Se o macOS impedir a abertura, registre a mensagem e a origem do build para diagnóstico. Não desative o Gatekeeper nem remova a quarentena como parte da instalação.

## Configurações

Abra o painel e clique em **Configurações**, ou use `⌘,`. A janela reúne Geral, Contas, Aparência, Avisos e Sobre. Ela mostra todos os provedores e oferece cadastro seguro de chave ou instruções de conexão. Provedores sem métricas ficam ocultos na barra e no painel de quotas, mas permanecem acessíveis nessa configuração.

## Codex

Instale o Codex CLI oficial e conclua a autenticação por seu fluxo oficial. O PlanMeter usa a sessão existente por meio do CLI e consulta apenas os métodos de conta e quota.

Se o executável não for encontrado, configure um caminho absoluto em `~/Library/Application Support/PlanMeter/config.json`:

```json
{
  "codexPath": "/caminho/absoluto/para/codex"
}
```

Preserve outras propriedades já presentes nesse arquivo. Não coloque tokens, senhas ou chaves nele.

## Claude Code

Em **Configurações → Contas**, selecione o Claude e escolha **Autorizar acesso**. Ative a consulta pela tela `/usage` do cliente oficial. O login permanece sob controle do Claude Code. Se houver um pedido de confiança para a pasta exclusiva de consulta, confirme-o no fluxo de configuração.

Para usar a alternativa passiva, escolha **Usar leitura passiva** no menu do Claude e depois **Copiar comando**. O caminho é absoluto e aponta para o configurador incluído no aplicativo; você pode executá-lo de qualquer pasta do Terminal.

O helper requer Python 3. Primeiro, inspecione a configuração:

```sh
python3 scripts/configure-claude.py --check
```

Para aplicar a integração:

```sh
python3 scripts/configure-claude.py --apply
```

O configurador faz backup e usa um wrapper para preservar uma statusline existente. O helper `scripts/claude-statusline-cache.py` recebe os dados da statusline e mantém o cache local utilizado pelo PlanMeter.

Os valores se renovam com a atividade normal do Claude Code. Um cache ausente ou antigo não comprova quota esgotada. Não inicie um turno de modelo só para testar o monitor.

## Z.ai

Em **Configurações → Contas → Z.ai**, escolha **Cadastrar chave** e digite sua chave no prompt seguro. Ela é armazenada no Keychain do macOS, no serviço `io.github.pcarielo.planmeter.zai`, conta `quota`.

Não passe a chave em comandos, argumentos, variáveis de ambiente ou arquivos de configuração. Para removê-la, use a opção correspondente no menu do aplicativo.

No modo automático por provedor, as consultas ocorrem a cada 15 minutos. Geral permite escolher outro intervalo. Consultas manuais respeitam um intervalo mínimo de 60 segundos. Respostas HTTP 429 também limitam novas tentativas.

## Kimi Code

Em **Configurações → Contas → Kimi Code**, escolha **Cadastrar chave** e cadastre a chave do Kimi Code/Coding Plan no prompt seguro. Ela fica no Keychain deste Mac. Chaves da plataforma Moonshot API são diferentes. O aplicativo não importa nem modifica o OAuth de outros programas.

A barra mostra separadamente o saldo de 5h e o semanal quando o provedor informa essas janelas. No modo automático por provedor, a coleta ocorre a cada 15 minutos; a manual respeita 60 segundos e eventuais restrições HTTP 429. Sem chave ou resposta válida, o aplicativo indica indisponibilidade.

## Grok Unified

Instale o [Grok Build oficial](https://docs.x.ai/build/overview) e autentique sua assinatura com `grok login`. O PlanMeter usa o cliente para ler quota e reset, sem copiar tokens nem enviar prompts. Quando a API confirma uso unificado, o cartão mostra a quota compartilhada entre produtos elegíveis.

## Usar o painel

Clique no indicador para abrir os cartões. Provedores sem métricas ficam ocultos; saldo zero continua visível. Use Atualizar para solicitar novas leituras, respeitando os intervalos de cada provedor.

Fixar mantém a janela aberta e permite arrastá-la pela faixa superior. Desafixar reativa o prazo configurado em Aparência, de 15 segundos por padrão. Os botões 1×, 1,25× e 1,5× ajustam o tamanho. O botão × fecha a janela e desativa a fixação. Configurações abre uma janela independente. Clique direito no indicador para acessar Configurações, histórico ou sair.

## Iniciar com a sessão

O início automático é opcional e pode ser ativado em **Configurações → Geral** depois da instalação em Aplicativos. A rota abaixo continua disponível para instalações antigas; não combine as duas formas:

```sh
./scripts/login-item.sh enable
./scripts/login-item.sh status
./scripts/login-item.sh disable
```

Também é possível ativá-lo na instalação com `./scripts/install.sh --login`.

## Desinstalar

```sh
./scripts/uninstall.sh
```

A desinstalação preserva os dados locais e a chave no Keychain. Se quiser remover a chave, faça isso pelo menu do aplicativo antes de desinstalá-lo. Decida separadamente se deseja excluir o histórico e as preferências em `~/Library/Application Support/PlanMeter/`.

## Edição e registros

Contas permite selecionar até dois planos no Free. Pro libera todos e os insights. As chaves de planos desativados são preservadas e podem ser removidas pelo menu da conta. Consulte [insights e simulação Free/Pro](insights.md) e [intervalos e logs](logs.md).
