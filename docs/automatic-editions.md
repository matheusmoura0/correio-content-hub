# Coleta, preparação e aprovação

O serviço `editorial_worker` do Compose executa um ciclo a cada 30 minutos. Ele
importa os feeds RSS ativos e prepara uma proposta para cada jornal habilitado.
Não faz buscas web nem chamadas de IA: a primeira versão usa as fontes RSS
cadastradas, a política de assuntos e o acervo recente. Erros de coleta são
registrados nos logs do worker sem interromper os outros feeds.

São escolhidas matérias dos últimos sete dias ainda não publicadas no destino,
com correspondência editorial e prontas segundo as regras de texto/imagem do
Hub. O texto precisa ter pelo menos 150 caracteres úteis; conteúdos futuros não
entram na fila. Uma mesma notícia pode ser proposta para jornais relacionados. Posições
manuais são preservadas. Posições automáticas podem receber novas sugestões;
espaços específicos de aviação exigem evidência desse assunto. Editorias são
sugeridas quando há correspondência simples; as demais exigem seleção do admin.

Há no máximo uma proposta pendente por jornal. O worker continua coletando e
mantém a proposta enquanto texto, política, editorias e página não mudarem. Se
ela ficar desatualizada, é encerrada como substituída e outra é preparada sem
publicar nada. As decisões já tomadas são preservadas. A proposta fica no
PostgreSQL e sobrevive a reinicializações do serviço.

Em Produtos > Para conferir, o administrador confere título, resumo, fonte,
imagem, texto completo e posição. Pode desmarcar matérias e ajustar editorias.
Aprovar e publicar pode ser usado por matéria ou em lote. Uma falha cancela todas
as publicações da ação. Itens não selecionados continuam pendentes. Recusar também
funciona por matéria ou em lote, sem retirar conteúdo publicado nem mudar outros
produtos. A mesma matéria recusada não volta a ser sugerida naquele produto,
mesmo depois de uma nova importação; continua disponível no acervo.

A aprovação verifica novamente assunto, direitos e prontidão. Se a matéria ou a
página tiver mudado desde a proposta, a aprovação é bloqueada até a atualização
automática. Formulários antigos também são bloqueados. A auditoria registra
administrador, horário e cada aprovação ou recusa. Publicações
manuais continuam disponíveis para administradores; repórteres não podem usar
os caminhos de publicação manual, automática ou em lote.

## Espaço do produto

A página inicial agora lista os jornais e revistas que recebem conteúdo do Hub,
com as pendências, rascunhos e matérias publicadas em cada destino. O Correio da
Manhã continua sendo apenas fonte de conteúdo, sem ações de publicação.

Cada produto reúne três etapas:

- **Para conferir**: proposta automática com texto completo expansível,
  seleção de matérias e editorias. Só administradores aprovam ou recusam.
- **Em produção**: acervo relacionado ao produto, originais e distribuições
  existentes, sem matérias que já estão publicadas nesse destino. A busca e o
  filtro Minhas matérias operam dentro do jornal selecionado.
- **No ar**: distribuições efetivamente publicadas naquele produto, com editoria
  e posição. Retirar uma matéria exige administrador e preserva o acervo e as
  publicações em outros jornais.

Escrever matéria a partir de um produto fixa seu destino. A edição de um original
usa o produto da fonte original, não uma distribuição posterior em outro jornal.
Posicionamento avançado e configurações permanecem disponíveis ao administrador;
o radar e o acervo geral continuam acessíveis como ferramentas auxiliares.

O painel mostra o último ciclo por produto, avisos de falha e decisões recentes.
Importação RSS apenas coleta e, quando há um destino configurado, cria rascunhos.
Ela nunca publica nem altera uma distribuição existente. Fontes sem autorização
de imagem não são liberadas automaticamente; a revisão de direitos continua
obrigatória. A coleta usa RSS cadastrado, não busca irrestrita ou redação com IA.

## VPS

Não execute o aplicativo, builds ou testes localmente. A implantação exige as
migrações `20261009120000` e `20261014120000` e a reconstrução de **web e
editorial_worker**. Faça backup do PostgreSQL antes da atualização e pare o
worker antigo antes de iniciar as migrações:

```bash
docker compose --env-file .env.production -f compose.production.yml stop editorial_worker
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

Confira também: decisão individual mantendo as demais pendentes; recusa que não
retorna em ciclos seguintes; recusa independente por produto; bloqueio de tela
antiga; substituição automática de proposta alterada; importação sem publicação;
histórico e contadores; layout e leitura no celular.

Há cobertura preparada em `test/services/publishing/suggestion_decisions_test.rb`,
não executada localmente. Execute apenas contra banco de teste isolado na VPS,
nunca o banco de produção. O fluxo visual também exige validação na VPS.
