# Coleta, preparação e aprovação

O serviço `editorial_worker` do Compose executa um ciclo a cada 30 minutos. Ele
importa os feeds RSS ativos e prepara uma proposta para cada jornal habilitado.
Não faz buscas web nem chamadas de IA: a primeira versão usa as fontes RSS
cadastradas, a política de assuntos e o acervo recente. Erros de coleta são
registrados nos logs do worker sem interromper os outros feeds.

São escolhidas matérias dos últimos sete dias ainda não publicadas no destino,
com correspondência editorial e prontas segundo as regras de texto/imagem do
Hub. Uma mesma notícia pode ser proposta para jornais relacionados. Posições
manuais são preservadas. Posições automáticas podem receber novas sugestões;
espaços específicos de aviação exigem evidência desse assunto. Editorias são
sugeridas quando há correspondência simples; as demais exigem seleção do admin.

Há no máximo uma proposta pendente por jornal. Enquanto o administrador confere
uma edição, o worker continua coletando sem substituir essa proposta. A edição
fica persistida no PostgreSQL e sobrevive a reinicializações do serviço.

Em Edições para aprovação, o administrador confere título, resumo, fonte, imagem,
texto completo e posição. Pode desmarcar matérias e ajustar editorias. Aprovar
e publicar selecionadas aplica o conjunto em uma transação: qualquer falha
cancela todas as mudanças de publicação. Itens desmarcados não são publicados.
Uma proposta pode ser descartada e refeita com o acervo disponível.

A aprovação verifica novamente assunto, direitos e prontidão. Se a matéria ou a
página tiver mudado desde a proposta, é necessário descartá-la e preparar outra.
A auditoria registra administrador, horário e matérias aprovadas. Publicações
manuais continuam disponíveis para administradores; repórteres não podem usar
os caminhos de publicação manual, automática ou em lote.

## VPS

Não execute o aplicativo, builds ou testes localmente. A implantação exige a
migração `20261009120000` e a reconstrução de **web e editorial_worker**:

```bash
docker compose --env-file .env.production -f compose.production.yml build web editorial_worker
docker compose --env-file .env.production -f compose.production.yml up -d --remove-orphans
docker compose --env-file .env.production -f compose.production.yml logs --tail=150 web editorial_worker
```

O worker aguarda o healthcheck do web após as migrações. O banco mantém um lock
para impedir ciclos de coleta simultâneos. O processo recomeça os ciclos após
reinício; não existe fila de tarefas persistida para cada feed.

Variáveis opcionais em `.env.production`:

```dotenv
EDITORIAL_AUTOMATION_ENABLED=true
EDITORIAL_INTERVAL_SECONDS=1800
EDITORIAL_MAX_AGE_DAYS=7
```

Valide na VPS: preparação sem mudanças na API pública; ausência de publicação
para usuário comum; aprovação de um subconjunto; rejeição de matéria alterada;
preservação de posições manuais; reinício do worker com proposta pendente.
