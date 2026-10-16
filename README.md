# Correio Content Hub

Beta privado para encontrar matérias por assunto, revisar conteúdos e produzir versões editoriais assistidas por IA.

## O que já existe no MVP

- autenticação de usuário com Devise;
- cadastro de sites;
- cadastro de categorias por site;
- cadastro de feeds RSS;
- importação manual de RSS com Feedjira;
- pesquisas salvas por palavras-chave, com correspondência por qualquer termo ou por todos;
- pesquisa direta na web com descoberta de fontes pela OpenAI e extração do conteúdo das páginas;
- pesca manual em todos os feeds ativos;
- reescrita assistida por IA usando a OpenAI Responses API;
- edição humana do título e texto gerados, mantendo a fonte original;
- gestão interna de até cinco usuários, sem cadastro público;
- deduplicação por URL e GUID;
- fila de matérias com status editorial;
- distribuição de uma matéria para múltiplos sites;
- API JSON para matérias publicadas por site.

## Stack

- Ruby on Rails 8
- PostgreSQL
- Devise
- Feedjira
- Rails server/Puma

Sidekiq e Redis ficam para uma segunda etapa. No MVP inicial, a importação é disparada manualmente pelo painel.

## Desenvolvimento local

### Pré-requisitos

- Ruby 3.2 ou superior
- Bundler
- PostgreSQL em execução

### Instalação

```bash
git clone https://github.com/matheusmoura0/correio-content-hub.git
cd correio-content-hub
git checkout develop
bundle install
```

Se o PostgreSQL local usar seu usuário do macOS sem senha, a configuração padrão deve funcionar. Caso contrário:

```bash
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=sua_senha
export POSTGRES_HOST=localhost
```

Depois:

```bash
bundle exec rails db:create
bundle exec rails db:migrate
bundle exec rails db:seed
bundle exec rails server
```

Para habilitar a reescrita por IA, configure no ambiente do servidor:

```bash
export OPENAI_API_KEY=sua_chave_da_openai
export OPENAI_MODEL=gpt-5.6-luna
```

O token nunca deve ser salvo no repositório ou enviado ao navegador.

## Deploy no Render

O repositório inclui um Blueprint em `render.yaml` e uma imagem Docker. Eles criam o serviço Rails e o PostgreSQL, executam as migrations e criam a primeira conta administrativa.

No primeiro deploy, o Render solicitará `OPENAI_API_KEY`, `ADMIN_EMAIL` e `ADMIN_PASSWORD`. Use uma senha forte com pelo menos 12 caracteres. O plano gratuito é adequado apenas para validar o beta: o serviço pode hibernar e o banco gratuito não deve ser tratado como ambiente definitivo sem uma rotina de backup.

Acesse:

```text
http://localhost:3000
```

### Login local padrão

Os seeds criam um usuário de desenvolvimento:

```text
E-mail: admin@correio.local
Senha: changeme123
```

Você pode sobrescrever esses valores antes de rodar `db:seed`:

```bash
export ADMIN_EMAIL=seu-email@exemplo.com
export ADMIN_PASSWORD=uma-senha-forte
```

## Fluxo de teste

1. Entre no painel com a conta administrativa.
2. Cadastre os feeds RSS que serão monitorados.
3. Abra **Pescar matérias**, crie uma pesquisa com palavras-chave e selecione Web, RSS ou ambos.
4. Clique em **Pescar matérias** para localizar e coletar matérias atuais.
5. Abra um resultado e clique em **Reescrever matéria**.
6. Revise e edite a versão gerada antes de aprová-la.
7. O administrador pode criar as demais contas em **Usuários**.

## API

Matérias publicadas para um site:

```text
GET /api/v1/sites/:site_id/articles
```

Matéria individual:

```text
GET /api/v1/articles/:id
```

## Modelos

- User
- Site
- Category
- Feed
- Article
- SiteArticle

## Fluxo

RSS → Importação → Banco de matérias → Revisão editorial → Distribuição → API → Sites

## Próximas etapas

- importação automática via Active Job/Sidekiq;
- regras de distribuição;
- seleção de categoria por distribuição;
- paginação e busca;
- tratamento avançado de imagens/enclosures RSS;
- logs de importação;
- testes automatizados;
- integração com o primeiro frontend do Correio Econômico.
- busca externa na web por meio de uma API de pesquisa;
- publicação de versões revisadas em sites estáticos.
