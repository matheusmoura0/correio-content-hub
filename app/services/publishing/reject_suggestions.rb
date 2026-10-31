module Publishing
  class RejectSuggestions
    def self.call(edition:, user:, item_ids:, article_digests:)
      raise ArgumentError, "Somente administradores podem recusar sugestões." unless user.admin?

      edition.site.with_lock do
        edition.lock!
        raise ArgumentError, "Esta proposta já foi encerrada. Atualize a tela." unless edition.status == "ready"
        items = edition.items.pending.where(id: item_ids).to_a
        raise ArgumentError, "Selecione ao menos uma sugestão pendente." if items.empty? || items.size != item_ids.size
        items.each do |item|
          raise ArgumentError, "As sugestões mudaram. Atualize a tela." unless article_digests[item.id.to_s] == item.article_digest

          item.update!(decision: "rejected", decided_by: user, decided_at: Time.current)
        end
        edition.finish_decisions!(user)
        ActivityLog.create!(user:, event: "editorial_editions.reject",
          description: "recusou #{items.size} sugestão(ões) para #{edition.site.name}",
          subject_type: "EditorialEdition", subject_id: edition.id)
      end
    end
  end
end
