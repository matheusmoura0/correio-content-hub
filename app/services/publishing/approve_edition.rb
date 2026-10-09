module Publishing
  class ApproveEdition
    def self.call(edition:, user:, item_ids:, categories:)
      raise ArgumentError, "Somente administradores podem aprovar uma edição." unless user.admin?

      edition.site.with_lock do
        edition.lock!
        raise ArgumentError, "Esta edição já foi encerrada." unless edition.status == "ready"
        if edition.page_digest != EditorialEdition.page_digest(edition.site)
          raise ArgumentError, "A página mudou desde a preparação. Descarte esta proposta e prepare uma nova."
        end
        items = edition.items.includes(:article).where(id: item_ids).to_a
        raise ArgumentError, "Selecione ao menos uma matéria desta edição." if items.empty? || items.size != item_ids.size

        # Validate every selected item before modifying any published position.
        choices = items.sort_by(&:article_id).to_h do |item|
          item.article.lock!
          if item.article.status == "ignored" || !item.article.publication_ready?
            raise ArgumentError, "A matéria #{item.title} não está mais pronta para publicação."
          end
          if item.article_digest != EditorialEdition.article_digest(item.article)
            raise ArgumentError, "A matéria #{item.title} mudou. Prepare uma nova edição antes de aprovar."
          end
          category = edition.site.categories.find_by(id: categories[item.id.to_s])
          raise ArgumentError, "Escolha uma editoria para #{item.title}." unless category
          raise ArgumentError, "Uma posição deixou de existir. Prepare uma nova edição." unless SiteProfile.for(edition.site).automatic_order.include?(item.slot_key)
          EditorialPolicy.new(edition.site).validate!(item.article)
          [item.id, category]
        end
        items.each do |item|
          PublishArticle.call(article: item.article, site: edition.site, category: choices.fetch(item.id),
            slot_key: item.slot_key, assignment_mode: "automatic")
          item.update!(category: choices.fetch(item.id), approved: true)
        end
        edition.update!(status: "approved", approved_by: user, approved_at: Time.current)
        ActivityLog.create!(user:, event: "editorial_editions.approve",
          description: "aprovou #{items.size} matéria(s) para #{edition.site.name}",
          subject_type: "EditorialEdition", subject_id: edition.id)
      end
    end
  end
end
