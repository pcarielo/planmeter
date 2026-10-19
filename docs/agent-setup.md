# Instalação assistida por agente

Este roteiro permite que um agente ajude a preparar o PlanMeter sem assumir autorização para autenticação, consumo de modelos ou mudanças na conta.

## Inspecionar primeiro

1. Leia `AGENTS.md`, `README.md` e `docs/getting-started.md`.
2. Confirme o diretório do repositório e as alterações locais existentes.
3. Execute `./scripts/doctor.sh` para diagnóstico somente por leitura.
4. Verifique os pré-requisitos e diferencie requisito mínimo de compatibilidade efetivamente testada.
5. Execute `./scripts/test.sh`, que usa fixtures.

Não procure segredos em arquivos pessoais, credenciais de outros aplicativos, histórico de shell ou variáveis de ambiente.

## Preparar os provedores

**Codex:** confirme que o CLI oficial está disponível. Se for necessário configurar `codexPath`, use um caminho absoluto e preserve outras propriedades do arquivo. O monitor consulta apenas `account/read` e `account/rateLimits/read`. Se a autenticação estiver ausente ou expirada, devolva o fluxo oficial ao usuário. Não inicie login, crie tokens ou execute turnos de modelo sem pedido específico.

**Claude Code:** execute `python3 scripts/configure-claude.py --check` antes de alterar a configuração. Quando a configuração da integração estiver autorizada, use `--apply`, que faz backup e preserva a statusline existente com um wrapper. Não substitua `statusLine` manualmente. O cache fica em `~/Library/Application Support/PlanMeter/claude-statusline.json`. Não abra uma sessão de modelo para forçar sua atualização.

**Z.ai:** oriente o usuário a cadastrar a chave no prompt seguro do menu do aplicativo. Não peça a chave no chat e não a passe por comandos, argumentos, ambiente ou configuração. A chave pertence ao Keychain do usuário. Em segundo plano, Keychain bloqueado significa dados indisponíveis, sem prompt de desbloqueio.

**Kimi Code:** use o cadastro seguro do menu para uma chave do Coding Plan. Não use chaves da plataforma Moonshot API nem leia arquivos OAuth do Kimi CLI. O usuário digita a chave diretamente no aplicativo. Verifique 5h e semanal separadamente depois do cadastro; os testes com fixtures não comprovam autenticação real.

## Instalar e validar

Quando a instalação local estiver autorizada, execute `./scripts/install.sh`. O destino padrão é `~/Applications/PlanMeter.app`. Confirme o resultado do script, a assinatura e a identidade do aplicativo instalado antes de declarar sucesso. Compilação concluída, por si só, não comprova instalação nem funcionamento dos provedores.

Abra o aplicativo instalado e verifique os estados exibidos. Registre separadamente testes com fixtures, build, instalação e consulta real. Não apresente dados antigos de cache como consulta atual.

O início automático exige uma escolha explícita: `./scripts/install.sh --login` ou `./scripts/login-item.sh enable`. Não o habilite por padrão.

Não remova quarentena, desative o Gatekeeper ou prometa notarização. O aplicativo usa assinatura ad hoc local e uma recompilação pode exigir que o usuário libere novamente o acesso no Keychain.

## Encerrar

Informe o que foi verificado, o que depende de atividade normal do Claude Code e qualquer autenticação que o usuário ainda precise concluir. Preserve histórico, preferências, cache e chaves. Publicação, push, compras, alterações de planos e mudanças em credenciais exigem autorização própria.
