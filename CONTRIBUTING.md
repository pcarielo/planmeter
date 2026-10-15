# Contribuir

Antes de mudar o aplicativo, leia [AGENTS.md](AGENTS.md), [README.md](README.md) e os documentos do componente afetado.

Use macOS 13 ou posterior com Xcode Command Line Tools. A validação real atual cobre Apple Silicon e macOS 26. Não declare suporte testado para outras combinações sem evidência.

## Mudanças e validação

1. Descreva o problema e o comportamento esperado.
2. Preserve mudanças locais de outras pessoas.
3. Use fixtures sintéticas nos testes e execute `./scripts/test.sh`.
4. Use `./scripts/doctor.sh` para verificar o ambiente sem alterá-lo.
5. Descreva no pull request o que mudou, como foi validado e o que ainda não foi verificado.

Não inclua chaves, tokens, caches reais, histórico de quotas, logs de clientes ou capturas com dados de conta. Testes não devem iniciar turnos de modelo, autenticação, SSH ou novas chamadas externas.

Instalação local é distinta de compilação. Antes de substituir um aplicativo em uso, confirme destino, assinatura e identidade do processo. Preserve estado e credenciais. Início automático é opcional.

Mudanças em provedores devem manter seus limites de acesso, política de atualização e tratamento de dados indisponíveis. Consulte [docs/providers.md](docs/providers.md) e [docs/security.md](docs/security.md).

## Licença

Ao contribuir, envie apenas material que você tem direito de licenciar. O código próprio é distribuído sob MIT. Marcas e ícones de terceiros seguem os termos de seus titulares, conforme [THIRD_PARTY.md](THIRD_PARTY.md).
