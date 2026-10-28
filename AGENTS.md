# PlanMeter: instruções para agentes

- Leia `README.md`, `docs/getting-started.md` e `docs/security.md` antes de alterar o aplicativo.
- Use este repositório como fonte canônica. Preserve alterações locais de outros colaboradores.
- Aplicativo instalado: `~/Applications/PlanMeter.app`. Estado local: `~/Library/Application Support/PlanMeter/`.
- Preserve caches, histórico, preferências e autenticação. Nunca versione segredos, snapshots reais de quotas, logs de clientes ou caches.
- Execute `./scripts/doctor.sh` para diagnóstico somente por leitura e `./scripts/test.sh` para testes com fixtures.
- Monitorar quotas não autoriza turnos ou sessões de modelo, login, alteração de planos, compras ou resets.
- Para monitorar quotas, Codex usa somente `account/read` e `account/rateLimits/read` pelo CLI oficial autenticado, via stdio. `codexPath`, quando configurado, é um caminho absoluto não secreto em `config.json`.
- Claude Code oferece leitura de `/usage` pelo CLI oficial e cache passivo da statusline. Nunca extraia tokens da assinatura nem use uma chamada de modelo para consultar quota. Coletas automáticas não podem aceitar confiança; a configuração manual exige confirmação explícita da pasta exclusiva pelo usuário. Inspecione com `python3 scripts/configure-claude.py --check`; aplique somente quando autorizado, usando `--apply`, que faz backup e preserva a statusline existente por wrapper.
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

- Insights são uma ação separada da coleta de quotas. Leia `docs/insights.md`: geração somente por ação explícita, com o modelo e o cliente escolhidos pelo usuário, resumo agregado e ferramentas desativadas. A assinatura Claude usa apenas o cliente oficial. Testes reais exigem autorização própria; os testes padrão usam fixtures.

## Cursor Cloud specific instructions

O aplicativo é Swift/AppKit. `./scripts/build.sh`, `./scripts/install.sh` e `./scripts/test.sh` exigem macOS e Xcode Command Line Tools. Neste Linux, não compile nem instale o aplicativo e não consulte provedores reais.

A validação com fixtures que roda aqui usa Python 3 e Node.js 18 ou posterior, já presentes na imagem:

- `./scripts/doctor.sh` faz o diagnóstico somente por leitura.
- `python3 tests/test_install.py` cobre instalação, item de login e desinstalação com comandos fictícios.
- `node tests/test_connect_proxy.js` sobe o gateway CONNECT local e confirma a recusa de hosts e endereços privados.
- `python3 tests/test_claude_integration.py` passa nos casos que usam os scripts do repositório. `test_bundled_setup_works_from_unrelated_directory` exige `build/PlanMeter.app` gerado no macOS.

Não há serviço de longa duração para iniciar.
