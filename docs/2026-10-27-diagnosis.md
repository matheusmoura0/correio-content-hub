# Diagnóstico do Hub em 27/10/2026

Inspeção por SSH, com consultas somente leitura no banco de produção. Web e
PostgreSQL estavam saudáveis, worker em execução, endpoint HTTPS /up com HTTP 200
e 87 GB livres no disco. O checkout estava em f68612c, sem alterações em arquivos
versionados. Nenhum teste foi executado no ambiente local.

## Problemas confirmados

- Aprovação retornando 422: a requisição para `/edicoes/36/approve` selecionou o
  item 445 sem editoria. A proposta era atual e a matéria estava pronta e dentro
  da política. A interface permitia enviar uma aprovação incompleta.
- Das 68 sugestões pendentes, 37 não tinham editoria e quatro apontavam para
  editorias de outro produto. O preparo reutilizava a categoria de uma
  distribuição legada sem confirmar sua propriedade.
- 133 distribuições antigas possuíam categoria de outro produto: 72 rascunhos
  e 61 publicadas. O ajuste limpa apenas os rascunhos e impede novas ocorrências;
  as 61 publicadas não são remapeadas automaticamente.
- CINEMAGAZINE recebeu sugestões sobre Fórmula 1 e investigação policial porque
  suas descrições continham “série de novidades” e “assassino em série”. A política
  tratava qualquer ocorrência de série como evidência de televisão.
- O worker repetia a extração de artigos já completos e tentava páginas bloqueadas
  em cada ciclo. Logs confirmaram respostas 403, timeouts e falhas 502 de RSS.
  Erros por entrada eram registrados, mas não refletidos no status da automação.
- A página de fontes ainda dizia que não havia coleta automática e que a
  importação publicava diretamente. Também carregava todos os textos do acervo
  apenas para contar as matérias de cada fonte.

## Escopo do ajuste

Retirar Jornal da Barra do Hub preservando seu histórico; impedir categorias de
outros produtos; sinalizar editorias obrigatórias antes da aprovação; exigir
contexto para palavras ambíguas de cinema; reduzir tentativas repetidas de
extração; mostrar avisos parciais de coleta; corrigir o estado mostrado nas fontes
e contar registros sem carregar seus textos.

Bloqueios e indisponibilidade da fonte exigem acompanhamento com seu responsável.
A correspondência temática ainda é baseada em regras, não análise semântica.
As categorias das 61 distribuições publicadas precisam de uma revisão separada.
