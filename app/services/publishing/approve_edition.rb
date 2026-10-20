module Publishing
  class ApproveEdition
    def self.call(edition:, user:, item_ids:, categories:, page_digest:, article_digests:)
      raise ArgumentError, "Somente administradores podem aprovar uma edição." unless user.admin?

      edition.site.with_lock do
        raise ArgumentError, "Este produto não recebe publicações do Hub." unless edition.site.publication_destination?
        edition.lock!
        raise ArgumentError, "Esta edição já foi encerrada." unless edition.status == "ready"
        raise ArgumentError, "As sugestões mudaram. Atualize a tela para conferir a versão mais recente." if page_digest != edition.page_digest
        if edition.page_digest != EditorialEdition.page_digest(edition.site)
          raise ArgumentError, "A página mudou. O próximo ciclo renovará as sugestões; confira novamente antes de aprovar."
        end
        items = edition.items.pending.includes(:article).where(id: item_ids).to_a
        raise ArgumentError, "Selecione ao menos uma matéria desta edição." if items.empty? || items.size != item_ids.size

        # Validate every selected item before modifying any published position.
        choices = items.sort_by(&:article_id).to_h do |item|
          item.article.lock!
          unless PrepareEdition.ready_candidate?(item.article)
            raise ArgumentError, "A matéria #{item.title} não está mais pronta para publicação."
          end
          if article_digests[item.id.to_s] != item.article_digest || item.article_digest != EditorialEdition.article_digest(item.article)
            raise ArgumentError, "A matéria #{item.title} mudou. O próximo ciclo renovará esta sugestão."
          end
          category = edition.site.categories.find_by(id: categories[item.id.to_s])
          raise ArgumentError, "Escolha uma editoria para #{item.title}." unless category
          raise ArgumentError, "Uma posição deixou de existir. Prepare uma nova edição." unless SiteProfile.for(edition.site).automatic_order.include?(item.slot_key)
          if edition.site.site_articles.where(status: "published", assignment_mode: "manual", slot_key: item.slot_key).exists?
            raise ArgumentError, "Esta posição foi reservada manualmente. Atualize as sugestões."
          end
          EditorialPolicy.new(edition.site).validate!(item.article)
          [item.id, category]
        end
        items.each do |item|
          PublishArticle.call(article: item.article, site: edition.site, category: choices.fetch(item.id),
            slot_key: item.slot_key, assignment_mode: "automatic")
          item.update!(category: choices.fetch(item.id), approved: true, decision: "approved", decided_by: user, decided_at: Time.current)
        end
        edition.finish_decisions!(user, approved: true)
        ActivityLog.create!(user:, event: "editorial_editions.approve",
          description: "aprovou #{items.size} matéria(s) para #{edition.site.name}",
          subject_type: "EditorialEdition", subject_id: edition.id)
      end
    end
  end
end
