module Analytics
  module AuthorIdentity
    def self.normalize(value)
      I18n.transliterate(value.to_s.unicode_normalize(:nfc)).squish.sub(/\Apor\s+/i, "").downcase
    end

    def self.sql
      "translate(lower(regexp_replace(regexp_replace(btrim(normalize(content_author, NFC)), " \
        "'[[:space:]]+', ' ', 'g'), '^por ', '', 'i')), " \
        "'áàâãäåéèêëíìîïóòôõöúùûüçñ', 'aaaaaaeeeeiiiiooooouuuucn')"
    end
  end
end
