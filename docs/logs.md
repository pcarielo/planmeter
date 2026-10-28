# Atualização e registros locais

Em **Configurações → Geral → Atualizações de quota**, escolha o intervalo automático: 1, 5, 15 ou 30 minutos, ou 1 hora. O padrão é Automático por provedor: Codex e Claude passivo a cada minuto; os demais coletores a cada 15 minutos. Um intervalo escolhido substitui esse padrão.

O intervalo escolhido não remove os limites dos provedores. Uma consulta já em andamento não é duplicada. As consultas manuais respeitam o prazo mínimo e eventuais respostas de limitação do serviço. O aplicativo informa quando é necessário aguardar.

## Avançado

O painel **Avançado: registros locais** permite ativar ou desativar três categorias:

- **Consultas:** início e resultado das leituras.
- **Configurações:** registro das alterações feitas no aplicativo.
- **Acessos e chaves:** resultado de cadastro, remoção ou autorização, sem o valor da credencial.

Cada categoria tem um botão **Visualizar**. Ele abre o arquivo corrente. **Abrir pasta de logs e arquivos anteriores** dá acesso também aos segmentos já rotacionados.

A pasta padrão é:

```text
~/Library/Application Support/PlanMeter/Logs/
```

A retenção cobre os arquivos desta pasta. Registros mantidos pelos clientes externos seguem a configuração deles.

O caminho aparece nas Configurações. Os arquivos usam JSONL, com um evento por linha. Datas ficam em timestamp Unix; categoria e operação identificam o tipo de evento. Não são guardadas respostas brutas dos serviços, chaves, tokens, prompts, transcrições ou dados de projetos.

## Rotação e retenção

A rotação pode ocorrer por tamanho, por período ou pelos dois critérios. O limite de tamanho por arquivo vai de 1 a 100 MB. O período pode ser diário, semanal ou de 30 dias, ou ficar desativado.

O padrão é 10 MB, rotação diária e retenção de pelo menos três meses completos. Quando 90 dias forem menos que três meses de calendário, vale o prazo maior. Você pode aumentar a retenção.

Rotacionar separa os registros em arquivos menores. Não apaga arquivos recentes para obedecer ao limite de tamanho. Só os arquivos que já passaram da retenção podem ser removidos automaticamente.

O aplicativo avisa quando há pouco espaço em disco ou quando não consegue gravar. Os registros ainda dentro da retenção são preservados. A pasta usa permissão privada, e os arquivos são criados para leitura e escrita somente pelo usuário do aplicativo.
