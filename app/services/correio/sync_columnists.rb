module Correio
  class SyncColumnists
    HOME = "https://www.correiodamanha.com.br/".freeze
    Result = Data.define(:updated, :failed, :skipped)

    def self.call(force: false, max_duration: 30)
      new.call(force: force, max_duration: max_duration)
    end

    def call(force:, max_duration:)
      counts = { updated: 0, failed: 0, skipped: true }
      site = Site.where(active: true).find(&:correio_source?)
      return Result.new(**counts) unless site

      ActiveRecord::Base.connection_pool.with_connection do |connection|
        return Result.new(**counts) unless connection.select_value("SELECT pg_try_advisory_lock(1952999, 3102)")
        begin
          site.reload
          return Result.new(**counts) if !force && site.analytics_profiles_checked_at && site.analytics_profiles_checked_at > 24.hours.ago

          site.update_column(:analytics_profiles_checked_at, Time.current)
          counts[:skipped] = false
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          document = fetch_document(HOME)
          entries(document).first(24).each do |entry|
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= max_duration

            profile = site.analytics_author_profiles.find_or_initialize_by(slug: entry.fetch(:slug))
            portrait = entry[:image_url]
            unless portrait
              begin
                detail = fetch_document(entry.fetch(:source_url))
                image = detail.at_css(".legacy-editoria-columnist-avatar img")
                portrait = photo(image&.[]("src"), entry.fetch(:source_url))
              rescue StandardError => error
                counts[:failed] += 1
                Rails.logger.warn("Foto do perfil #{entry[:slug]} indisponível: #{error.class}")
              end
            end
            name = entry.fetch(:name)
            aliases = [name]
            if entry[:slug] == "magnavita"
              name = "Cláudio Magnavita"
              aliases << "Cláudio Magnavita" << "Magnavita"
            end
            profile.assign_attributes(name: name, source_url: entry.fetch(:source_url),
              aliases: (profile.aliases + aliases).uniq, individual: !entry[:slug].start_with?("correio-"), checked_at: Time.current)
            profile.image_url = portrait if portrait
            profile.save!
            counts[:updated] += 1
          rescue StandardError => error
            counts[:failed] += 1
            Rails.logger.warn("Perfil de colunista #{entry[:slug]}: #{error.class}: #{error.message}")
          end
        ensure
          connection.execute("SELECT pg_advisory_unlock(1952999, 3102)")
        end
      end
      Result.new(**counts)
    rescue StandardError => error
      Rails.logger.warn("Catálogo de colunistas: #{error.class}: #{error.message}")
      Result.new(updated: counts[:updated], failed: counts[:failed] + 1, skipped: counts[:skipped])
    end

    def entries(document)
      profiles = {}
      document.css("a[href]").each do |anchor|
        value = URI.join(HOME, anchor["href"]).to_s
        next unless AnalyticsAuthorProfile.trusted_url?(value)
        uri = URI.parse(value)
        match = uri.path.match(%r{\A/colunistas/([a-z0-9]+(?:-[a-z0-9]+)*)/?\z})
        next unless match && uri.query.nil? && uri.fragment.nil?

        slug = match[1]
        name = anchor.at_css("h3")&.text&.squish.presence || anchor.text.squish
        next if name.blank? || name.length > 100

        profiles[slug] ||= { slug: slug, name: name, source_url: "#{HOME}colunistas/#{slug}" }
        image = anchor.at_css("img.cm-home-columnist-avatar, img.magnavita-avatar")
        portrait = photo(image&.[]("src"), HOME)
        profiles[slug][:image_url] = portrait if portrait
      rescue URI::InvalidURIError
        next
      end
      profiles.values
    end

    private

    def fetch_document(url)
      document, final_url = Web::ExtractArticle.document(url)
      raise "Perfil redirecionado para fora do Correio" unless AnalyticsAuthorProfile.trusted_url?(final_url)

      document
    end

    def photo(value, base_url)
      image = Web::ArticleImage.normalize(value, base_url: base_url)
      image if image && AnalyticsAuthorProfile.trusted_url?(image)
    end
  end
end
