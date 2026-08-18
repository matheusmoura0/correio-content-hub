# Correio Content Hub

MVP de uma ferramenta central para ingestão, gestão e distribuição de conteúdos via RSS para múltiplos portais do Correio.

## Objetivo do MVP

O sistema será responsável por:

- cadastrar sites e domínios;
- cadastrar fontes RSS;
- importar matérias automaticamente;
- evitar conteúdo duplicado;
- organizar matérias em uma fila editorial;
- distribuir uma mesma matéria para um ou mais sites;
- disponibilizar conteúdo publicado por meio de uma API JSON.

## Stack inicial

- Ruby on Rails
- PostgreSQL
- Hotwire / Turbo
- Devise
- Feedjira
- Active Job inicialmente
- Sidekiq + Redis em uma etapa posterior

## Modelos previstos

- User
- Site
- Category
- Feed
- Article
- SiteArticle

## Fluxo inicial

RSS → Importação → Banco de matérias → Revisão editorial → Distribuição → API → Sites

## Desenvolvimento local

A primeira fase do projeto será desenvolvida e validada localmente antes de qualquer deploy em produção.
