# PlanMeter: instruções para agentes

- Leia `README.md`, `docs/getting-started.md` e `docs/security.md` antes de alterar o aplicativo.
- Use este repositório como fonte canônica. Preserve alterações locais de outros colaboradores.
- Aplicativo instalado: `~/Applications/PlanMeter.app`. Estado local: `~/Library/Application Support/PlanMeter/`.
- Preserve caches, histórico, preferências e autenticação. Nunca versione segredos, snapshots reais de quotas, logs de clientes ou caches.
- Execute `./scripts/doctor.sh` para diagnóstico somente por leitura e `./scripts/test.sh` para testes com fixtures.
- Monitorar quotas não autoriza turnos de modelo, criação de sessões, login, alteração de planos, compras ou resets.
- Codex usa somente `account/read` e `account/rateLimits/read` pelo CLI oficial autenticado, via stdio. `codexPath`, quando configurado, é um caminho absoluto não secreto em `config.json`.
- Claude Code usa cache da statusline. Inspecione com `python3 scripts/configure-claude.py --check`; aplique somente quando autorizado, usando `--apply`, que faz backup e preserva a statusline existente por wrapper.
- Não inicie atividade de modelo para renovar o cache Claude. Cache antigo ou ausente não significa quota zero.
- As chaves Z.ai e Kimi Code são cadastradas pelo usuário no prompt seguro do aplicativo e armazenadas no Keychain. Nunca as peça em chat ou as passe em argumentos, ambiente, logs ou configuração. Não leia credenciais de outros aplicativos.
- Não amplie chamadas externas, SSH, autenticação ou infraestrutura para testes. Use dados sintéticos.
- Compilar não instala. Antes de substituir o aplicativo, confira testes, assinatura, destino e identidade do processo. Reinicie somente o monitor autorizado.
- Não habilite início automático por padrão. `--login` e `login-item.sh enable` dependem de escolha explícita do usuário.
- O build local usa assinatura ad hoc. Não prometa notarização, assinatura Developer ID ou compatibilidade que não foi testada. Não remova quarentena nem desative o Gatekeeper.
- Push, publicação, compras, alterações de plano e mudanças de credenciais exigem autorização explícita.
- Ao delegar, use XML, YAML ou JSON para delimitar escopo, propriedade dos arquivos, contratos e evidências esperadas.
- Relate separadamente validação com fixtures, compilação, instalação e observação real dos provedores.

- Grok usa o Grok Build oficial autenticado, via ACP: somente `initialize` e `_x.ai/billing`. Não leia auth.json, cookies ou tokens, não use `session/new`/`session/prompt` e não substitua quota compartilhada por créditos financeiros da API. Testes usam CLI fictício e recusam solicitações de ferramentas do servidor.
