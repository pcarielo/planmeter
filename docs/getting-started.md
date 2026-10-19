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

No menu do PlanMeter, escolha configurar a chave Z.ai e digite sua chave no prompt seguro. Ela é armazenada no Keychain do macOS, no serviço `io.github.pcarielo.planmeter.zai`, conta `quota`.

Não passe a chave em comandos, argumentos, variáveis de ambiente ou arquivos de configuração. Para removê-la, use a opção correspondente no menu do aplicativo.

As consultas automáticas ocorrem a cada 15 minutos. Consultas manuais respeitam um intervalo mínimo de 60 segundos. Respostas HTTP 429 também limitam novas tentativas.

## Kimi Code

Escolha **Kimi: configurar chave…** no menu e cadastre a chave do Kimi Code/Coding Plan no prompt seguro. Ela fica no Keychain deste Mac. Chaves da plataforma Moonshot API são diferentes. O aplicativo não importa nem modifica o OAuth de outros programas.

A barra mostra separadamente o saldo de 5h e o semanal quando o provedor informa essas janelas. A coleta automática ocorre a cada 15 minutos; a manual respeita 60 segundos e eventuais restrições HTTP 429. Sem chave ou resposta válida, o aplicativo indica indisponibilidade.

## Grok Unified

Instale o [Grok Build oficial](https://docs.x.ai/build/overview) e autentique sua assinatura com `grok login`. O PlanMeter usa o cliente para ler quota e reset, sem copiar tokens nem enviar prompts. Quando a API confirma uso unificado, o cartão mostra a quota compartilhada entre produtos elegíveis.

## Usar o painel

Clique no indicador para abrir os cartões. Provedores sem métricas ficam ocultos; saldo zero continua visível. Use Atualizar para solicitar novas leituras, respeitando os intervalos de cada provedor.

Fixar mantém a janela aberta e permite arrastá-la pela faixa superior. Desafixar reativa o fechamento após 15 segundos. Os botões 1×, 1,25× e 1,5× ajustam o tamanho. O botão × fecha a janela. Clique direito no indicador para configurar chaves, acessar histórico ou sair.

## Iniciar com a sessão

O início automático é opcional:

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
