# Idiomas

O PlanMeter oferece English, Español, Português, 한국어, 日本語, Français, 繁體中文 e हिन्दी.

## Escolher um idioma

Abra Configurações → Idioma. A opção inicial segue o idioma principal do macOS. Quando ele não é oferecido, o aplicativo usa inglês. Você também pode escolher um dos oito idiomas diretamente. A escolha atualiza a interface imediatamente e fica salva para as próximas aberturas.

A tradução em português é brasileira e aparece no seletor apenas como Português. O chinês oferecido é tradicional; um sistema configurado em chinês simplificado usa o fallback inglês até que você escolha outro idioma.

As traduções ficam no próprio aplicativo. Mudar o idioma não consulta modelos, não altera as credenciais nem escolhe outros planos. Histórico, seleção de provedores e preferências da barra são preservados. Datas usam o idioma escolhido e o fuso horário atual do Mac. Identificadores internos e nomes oficiais dos clientes permanecem estáveis.

Diálogos do macOS, como os pedidos de acesso ao Keychain, seguem as configurações do sistema. Os comandos dos clientes continuam no formato oficial para copiar e executar.

## Desenvolvimento

Os catálogos ficam em app/Resources/Locales, um JSON por idioma. O inglês é o fallback para uma tradução ausente. Mensagens parametrizadas usam placeholders numerados, como %1$@, que podem mudar de posição sem alterar o valor inserido.

Use L(...) para textos apresentados ao usuário. Nunca aplique localização a serviços ou contas do Keychain, métodos de protocolo, caminhos, IDs de modelos ou nomes persistidos que identificam janelas de quota. Nesses casos, traduza apenas a apresentação. A suíte verifica catálogos, placeholders, seleção do idioma, migração de preferências e identidade do histórico entre idiomas.
