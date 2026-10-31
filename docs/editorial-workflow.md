# Fluxo editorial por jornal

Na Produção, escolha o jornal, filtre a situação e use Minhas matérias para
encontrar reportagens próprias. O jornal escolhido é lembrado durante a sessão
e usado como destino inicial ao escrever. Cada página mostra até 30 matérias.

Reportagens próprias exigem uma editoria do jornal selecionado. Rascunhos ficam
no acervo desse jornal mesmo quando o texto ainda não tem correspondência
editorial. Editar uma reportagem publicada devolve suas distribuições à revisão.

## Assuntos permitidos

Em Sites, os administradores configuram os assuntos aceitos por vírgula ou linha.
A migração inicial preenche termos para turismo, aviação, cinema, teatro,
gastronomia, economia e cobertura da Barra, conforme as publicações existentes.
Jornais sem termos configurados bloqueiam novas publicações até a configuração.

A validação considera título, resumo e, para conteúdos externos, a URL da
matéria e os dados do feed e de sua categoria. Ignora diferenças de caixa e
acentuação e exige palavras completas. Para conteúdo escrito no Hub, o nome
do jornal e a URL interna não são usados como prova de correspondência.

Essa regra é uma correspondência de termos, não uma análise semântica. Pode
rejeitar textos relevantes sem esses termos ou aceitar textos que os mencionem
sem serem o assunto principal. A revisão humana continua necessária. Revise
os termos de cada jornal na VPS usando matérias representativas da redação.

O bloqueio vale para publicação manual, automática, em lote e para publicação
direta em Gastronomia. A categoria deve pertencer ao destino. Não há exceção
para administradores. O preenchimento automático e a seleção de matérias da
central de publicação usam a mesma política.

Publicações existentes não são retiradas automaticamente pela migração.
Reavalie-as na VPS; novas publicações e atualizações de distribuição passam
pela validação. A configuração editorial não é um controle de acesso ao acervo.

## Implantação

Esta atualização exige a migração `20261007120000`. Faça backup do banco antes
do deploy. O entrypoint da imagem de produção executa as migrações na partida.
Valide na VPS uma matéria compatível, uma fora do tema e uma reportagem própria,
incluindo revisão, publicação e edição posterior. Não execute testes locais.
