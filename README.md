# Correio Content Hub

Beta privado para encontrar matérias por assunto, revisar conteúdos e produzir versões editoriais assistidas por IA.

## O que já existe no MVP

- autenticação de usuário com Devise;
- cadastro de sites;
- cadastro de categorias por site;
- cadastro de feeds RSS;
- importação manual de RSS com Feedjira;
- pesquisas salvas por palavras-chave, com correspondência por qualquer termo ou por todos;
- pesca manual em todos os feeds ativos;
- reescrita assistida por IA usando GitHub Models;
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
export GITHUB_MODELS_TOKEN=seu_token_com_permissao_models_read
export GITHUB_MODELS_MODEL=openai/gpt-4.1-mini
```

O token nunca deve ser salvo no repositório ou enviado ao navegador.

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
3. Abra **Pescar matérias** e crie uma pesquisa com palavras-chave.
4. Clique em **Pescar matérias** para atualizar os feeds e localizar correspondências.
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
