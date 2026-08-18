# Correio Content Hub

MVP de uma ferramenta central para ingestão, gestão e distribuição de conteúdos via RSS para múltiplos portais do Correio.

## O que já existe no MVP

- autenticação de usuário com Devise;
- cadastro de sites;
- cadastro de categorias por site;
- cadastro de feeds RSS;
- importação manual de RSS com Feedjira;
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

1. Entre no painel.
2. Cadastre um site.
3. Cadastre uma categoria para esse site.
4. Cadastre um feed RSS e associe-o ao site/categoria.
5. Clique em **Importar agora**.
6. Abra **Matérias**.
7. Revise a matéria, selecione os sites de distribuição e altere o status para `published`.
8. Consulte a API.

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
