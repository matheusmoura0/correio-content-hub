require "prawn"
require "stringio"

module Analytics
  class PdfReport
    RED = "AD1119".freeze
    INK = "20242A".freeze
    MUTED = "68707C".freeze
    LINE = "E2E5E9".freeze
    FONT_ROOT = "/usr/share/fonts/truetype/dejavu".freeze
    RANKING_LIMIT = 10
    SORT_LABELS = { "views" => "visualizações", "articles" => "conteúdos acessados",
      "clicks" => "cliques", "engagement_seconds" => "tempo registrado" }.freeze

    def initialize(report, images: PdfImages.new)
      @combined = report.site.correio_source?
      @images = images
      @report = @combined ? EditorialReport.new(site: report.site, from: report.from, to: report.to,
        filters: report.filters, dimension: "articles", sort: "views") : report
    end

    def call
      @total = @report.total_rows
      @rows = @report.rows(limit: RANKING_LIMIT)
      if @combined
        @columnist_report = EditorialReport.new(site: @report.site, from: @report.from, to: @report.to,
          filters: @report.filters, dimension: "columnists", sort: "views")
        @columnists = @columnist_report.rows(limit: RANKING_LIMIT)
        @article_paths = @report.site.analytics_events.where(content_key: @rows.map { |row| row[:key] },
          event_type: "page_view", occurred_at: @report.from...@report.to).group(:content_key).maximum(:path)
      end
      @pdf = Prawn::Document.new(page_size: "A4", margin: [94, 42, 52, 42],
        info: { Title: "#{@report.site.name} - Relatório de audiência", Author: "Correio da Manhã",
          Subject: "#{report_label}: #{period}", Creator: "CM Content Hub" })
      @pdf.font_families.update("EditorialSans" => {
        normal: "#{FONT_ROOT}/DejaVuSans.ttf", bold: "#{FONT_ROOT}/DejaVuSans-Bold.ttf"
      }, "EditorialSerif" => { normal: "#{FONT_ROOT}/DejaVuSerif.ttf", bold: "#{FONT_ROOT}/DejaVuSerif-Bold.ttf" })
      @pdf.font "EditorialSans", size: 9
      @pdf.fill_color INK
      overview
      measurement_notes
      if @combined
        illustrated_ranking(@columnist_report, @columnists, people: true)
        illustrated_ranking(@report, @rows, people: false)
      else
        ranking
      end
      chrome
      @pdf.render
    end

    private

    def overview
      @pdf.fill_color INK
      @pdf.font("EditorialSerif") { @pdf.text "Destaques de audiência", size: 24, style: :bold }
      @pdf.move_down 8
      @pdf.text "#{period} · dias completos em UTC", color: MUTED, size: 9
      @pdf.move_down 6
      @pdf.text "Comparação: #{date(@report.previous_from)} a #{date(@report.from - 1.second)}", color: MUTED, size: 8
      @pdf.move_down 14
      @pdf.text "#{report_label} · ordenação por #{SORT_LABELS.fetch(@report.sort)}", size: 10, style: :bold
      @pdf.move_down 4
      @pdf.text "#{@combined ? 'Até 10 posições em cada ranking.' : "Top #{@rows.length} de #{number(@total)} resultados."} O resumo considera todos os resultados filtrados.", size: 8, color: MUTED
      filter_labels = { q: "Busca", author: "Assinatura", columnist: "Colunista", category: "Editoria", article: "Matéria" }
      @report.filters.each do |key, value|
        label = value == Analytics::EditorialReport::MISSING ? "Não informado" : safe(key == :columnist ? @report.columnist_name : value, 100)
        @pdf.text "#{filter_labels.fetch(key)}: #{label}", size: 8, color: MUTED
      end
      @pdf.move_down 16
      summary = @report.summary
      previous = @report.summary(previous: true)
      start_y = @pdf.cursor
      cell_width = (@pdf.bounds.width - 12) / 2
      [[:views, "Visualizações"], [:visitors, "Identificadores de visitantes/dia"],
        [:articles, "Conteúdos acessados"], [:clicks, "Cliques registrados"]].each_with_index do |(key, label), index|
        @pdf.bounding_box([(index % 2) * (cell_width + 12), start_y - (index / 2) * 86], width: cell_width, height: 74) do
          @pdf.fill_color "F4F5F6"
          @pdf.fill_rectangle [0, 74], cell_width, 74
          @pdf.fill_color INK
          @pdf.text_box label, at: [12, 63], width: cell_width - 24, size: 8
          @pdf.text_box number(summary[key]), at: [12, 46], width: cell_width - 24, size: 22, style: :bold
          @pdf.fill_color MUTED
          @pdf.text_box "Anterior: #{number(previous[key])} · #{change(@report.comparison[key])}",
            at: [12, 16], width: cell_width - 24, size: 7
        end
      end
      @pdf.move_cursor_to start_y - 174
      daily_chart
      @pdf.move_down 12
      @pdf.text "Tempo registrado em todos os resultados filtrados: #{duration(summary[:engagement_seconds])}.", size: 8, color: MUTED
    end

    def daily_chart
      @pdf.text "Evolução diária de visualizações", size: 11, style: :bold
      @pdf.move_down 5
      @pdf.text "Vermelho: período atual · Cinza: período anterior equivalente", size: 7, color: MUTED
      @pdf.move_down 10
      daily = @report.daily_views
      prior = @report.daily_views(previous: true)
      peak = [daily.map { |day| day[:views] }.max.to_i, prior.map { |day| day[:views] }.max.to_i, 1].max
      @pdf.text "Escala: 0 a #{number(peak)} visualizações/dia", size: 7, color: MUTED
      width = @pdf.bounds.width
      @pdf.fill_color INK
      @pdf.bounding_box([0, @pdf.cursor], width: width, height: 120) do
        step = width / [daily.length, 1].max
        daily.each_with_index do |day, index|
          [[prior[index]&.dig(:views).to_i, "C9CED4", 0.08], [day[:views], RED, 0.52]].each do |count, color, offset|
            next if count.zero?
            height = count * 90.0 / peak
            @pdf.fill_color color
            @pdf.fill_rectangle [index * step + step * offset, 18 + height], step * 0.38, height
          end
        end
        @pdf.stroke_color LINE
        @pdf.stroke_horizontal_line 0, width, at: 18
        @pdf.fill_color MUTED
        @pdf.text_box date(@report.from), at: [0, 10], size: 7
        @pdf.text_box date(@report.to - 1.second), at: [width - 100, 10], width: 100, align: :right, size: 7
        @pdf.fill_color INK
      end
    end

    def ranking
      @pdf.start_new_page
      ranking_heading
      if @rows.empty?
        @pdf.move_down 20
        @pdf.text "Nenhum resultado para o período e os filtros selecionados.", color: MUTED
        return
      end
      @rows.each_with_index do |row, index|
        name = safe(row[:name], 180)
        detail = if @report.dimension == "articles"
          "#{safe(row[:author], 160)} · #{safe(row[:category], 100)}"
        else
          "#{number(row[:articles])} matérias · mediana #{row[:median_views]} · #{duration(row[:engagement_seconds])}"
        end
        metric = @report.sort.to_sym
        previous = row["previous_#{metric}".to_sym].to_i
        cells = [number(index + 1), "#{name}\n#{detail}", metric_value(row, metric),
          metric == :engagement_seconds ? duration(previous) : number(previous),
          change(@report.change(row[metric], previous)), metric_value(row, supporting_metric)]
        height = [cells.each_with_index.map { |text, i| @pdf.height_of(text, width: widths[i] - 12, size: 8, leading: 2) }.max + 20, 44].max
        if @pdf.cursor < height + 8
          @pdf.start_new_page
          ranking_heading
        end
        top = @pdf.cursor
        @pdf.fill_color index.even? ? "F5F6F7" : "FFFFFF"
        @pdf.fill_rectangle [0, top], @pdf.bounds.width, height
        @pdf.fill_color INK
        x = 0
        cells.each_with_index do |text, i|
          @pdf.text_box text, at: [x + 6, top - 10], width: widths[i] - 12, height: height - 16,
            size: 8, leading: 2, align: i > 1 ? :right : :left
          x += widths[i]
        end
        @pdf.move_cursor_to top - height
      end
    end

    def illustrated_ranking(report, rows, people:)
      total = report.total_rows
      rows.each_slice(people ? 10 : 5).with_index do |page_rows, page_index|
        @pdf.start_new_page
        illustrated_heading(report, rows.length, total, people)
        page_rows.each_with_index do |row, local_index|
          index = page_index * (people ? 10 : 5) + local_index
          top = @pdf.cursor
          height = people ? 60 : 112
          @pdf.fill_color local_index.even? ? "F4F5F6" : "FFFFFF"
          @pdf.fill_rectangle [0, top], @pdf.bounds.width, height
          @pdf.fill_color RED
          @pdf.text_box number(index + 1), at: [8, top - 12], width: 23, size: 11, style: :bold
          image_width = people ? 42 : 94
          image_height = people ? 42 : 70
          portrait(row, people, at: [38, top - 9], width: image_width, height: image_height)
          x = 38 + image_width + 12
          name_width = @pdf.bounds.width - x - (people ? 116 : 14)
          @pdf.fill_color INK
          @pdf.text_box safe(row[:name], people ? 80 : 180), at: [x, top - 10], width: name_width,
            height: people ? 27 : 53, size: people ? 11 : 10, leading: 2, style: :bold
          @pdf.fill_color MUTED
          if people
            @pdf.text_box "#{number(row[:articles])} matérias com assinatura individual", at: [x, top - 40],
              width: name_width, height: 14, size: 8
            @pdf.fill_color INK
            @pdf.text_box number(row[:views]), at: [@pdf.bounds.width - 110, top - 10], width: 100,
              height: 20, size: 16, style: :bold, align: :right
            @pdf.fill_color MUTED
            @pdf.text_box "visualizações\nAnterior: #{number(row[:previous_views])} · #{change(row[:views_change])}",
              at: [@pdf.bounds.width - 120, top - 31], width: 110, height: 24, size: 7, align: :right
          else
            @pdf.text_box "#{safe(row[:author], 75)} · #{safe(row[:category], 55)}", at: [x, top - 64],
              width: name_width, height: 23, size: 8
            @pdf.fill_color INK
            @pdf.text_box "#{number(row[:views])} visualizações · Anterior: #{number(row[:previous_views])} · #{change(row[:views_change])}",
              at: [x, top - 91], width: name_width, height: 14, size: 8, style: :bold
            if (url = article_url(row))
              @pdf.fill_color RED
              @pdf.formatted_text_box [{ text: "Ler matéria", link: url }], at: [38, top - 86],
                width: image_width, height: 15, size: 8
            end
          end
          @pdf.move_cursor_to top - height
        end
      end
      if rows.empty?
        @pdf.start_new_page
        illustrated_heading(report, 0, total, people)
        @pdf.text "Nenhum resultado para o período e os filtros selecionados.", color: MUTED
      end
    end

    def illustrated_heading(report, count, total, people)
      @pdf.fill_color INK
      @pdf.text "#{people ? 'Colunistas em destaque' : 'Notícias mais vistas'}", size: 19, style: :bold
      @pdf.move_down 7
      @pdf.text "Top #{count} de #{number(total)} · #{period} · ordem por visualizações", size: 8, color: MUTED
      @pdf.move_down 8
      @pdf.text people ? "Somente matérias assinadas individualmente por cada colunista." : "Manchetes, autoria e acessos registrados no período selecionado.", size: 8, color: MUTED
      @pdf.move_down 18
    end

    def portrait(row, people, at:, width:, height:)
      bytes = @images.call(people ? row[:author_image_url] : row[:image_url])
      if bytes
        @pdf.image StringIO.new(bytes), at: at, fit: [width, height], position: :center
      else
        @pdf.fill_color "E2E5E9"
        @pdf.fill_rectangle at, width, height
        @pdf.fill_color MUTED
        label = people ? row[:name].split.map(&:first).first(2).join.upcase : "CM"
        @pdf.text_box safe(label, 3), at: [at[0], at[1] - height / 2 + 8], width: width, height: 18, size: 12, align: :center
      end
    rescue Prawn::Errors::UnsupportedImageType, Prawn::Errors::ImageMissing
      nil
    end

    def article_url(row)
      path = @article_paths[row[:key]].to_s
      return unless path.start_with?("/") && !path.start_with?("//")
      uri = URI.join("https://www.correiodamanha.com.br", path)
      return unless PdfImages.new.allowed?(uri.to_s)
      uri.query = uri.fragment = nil
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def report_label
      @combined ? "Colunistas e notícias mais vistas" : @report.label
    end

    def ranking_heading
      @pdf.text "Top #{@rows.length} · #{@report.label}", size: 17, style: :bold
      @pdf.move_down 5
      @pdf.text "#{number(@rows.length)} de #{number(@total)} resultados · #{period} · ordem por #{SORT_LABELS.fetch(@report.sort)}", size: 8, color: MUTED
      @pdf.move_down 14
      top = @pdf.cursor
      @pdf.fill_color INK
      @pdf.fill_rectangle [0, top], @pdf.bounds.width, 30
      @pdf.fill_color "FFFFFF"
      x = 0
      metric_labels = { "views" => "Visualizações", "articles" => "Conteúdos", "clicks" => "Cliques", "engagement_seconds" => "Tempo" }
      ["#", @report.dimension == "articles" ? "Matéria / assinatura" : "Nome / conteúdos", metric_labels.fetch(@report.sort), "Anterior", "Variação", metric_labels.fetch(supporting_metric.to_s)].each_with_index do |text, i|
        @pdf.text_box text, at: [x + 6, top - 10], width: widths[i] - 12, height: 18,
          size: 7, align: i > 1 ? :right : :left
        x += widths[i]
      end
      @pdf.fill_color INK
      @pdf.move_cursor_to top - 30
    end

    def measurement_notes
      @pdf.move_down 12
      @pdf.fill_color INK
      @pdf.text "Notas de medição", size: 10, style: :bold
      @pdf.move_down 6
      notes = @combined ? @columnist_report.notes : @report.notes
      notes.each { |note| @pdf.text safe(note), size: 7, color: MUTED, leading: 1; @pdf.move_down 3 }
      @pdf.text "O relatório destaca até #{RANKING_LIMIT} posições #{@combined ? 'em cada ranking, por visualizações' : 'pela métrica selecionada'}. Títulos acima de 180 caracteres são abreviados. O ranking completo permanece no painel.", size: 7, color: MUTED
      @pdf.move_down 5
      @pdf.text "Fonte: tag de audiência do #{@report.site.name}. Emitido em #{Time.current.strftime('%d/%m/%Y às %H:%M')} (Brasília).", size: 7, color: MUTED
    end

    def chrome
      width = @pdf.bounds.width
      (1..@pdf.page_count).each do |page_number|
        @pdf.go_to_page(page_number)
        @pdf.canvas do
          @pdf.bounding_box([42, @pdf.page.dimensions[3] - 36], width: width, height: 44) do
            @pdf.fill_color RED
            @pdf.fill_rectangle [0, 44], 36, 36
            @pdf.font("EditorialSerif") do
              @pdf.fill_color "FFFFFF"
              @pdf.text_box "CM", at: [2, 35], width: 32, align: :center, size: 15, style: :bold
              @pdf.fill_color INK
              @pdf.text_box safe(@report.site.name, 80), at: [48, 43], width: @pdf.bounds.width - 48, size: 18, style: :bold
            end
            @pdf.fill_color MUTED
            @pdf.text_box "RELATÓRIO DE AUDIÊNCIA · #{report_label.upcase}", at: [48, 17], size: 7
          end
          @pdf.stroke_color LINE
          @pdf.stroke_horizontal_line 42, 42 + width, at: 40
          @pdf.fill_color MUTED
          @pdf.text_box "Correio da Manhã · Audiência editorial", at: [42, 28], width: 300, height: 12, size: 7
        end
      end
      @pdf.number_pages "Página <page> de <total>",
        at: [@pdf.bounds.width - 140, -24], width: 140, align: :right, size: 7, color: MUTED
    end

    def widths
      @widths ||= [0.065, 0.415, 0.14, 0.13, 0.12, 0.13].map { |part| @pdf.bounds.width * part }
    end

    def supporting_metric
      @report.sort == "clicks" ? :views : :clicks
    end

    def metric_value(row, metric)
      metric == :engagement_seconds ? duration(row[metric]) : number(row[metric])
    end

    def safe(value, length = 1000)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace).gsub(/[\u0000-\u001f\u007f]/, " ").truncate(length)
    end

    def number(value)
      ActiveSupport::NumberHelper.number_to_delimited(value.to_i, delimiter: ".")
    end

    def date(value)
      value.strftime("%d/%m/%Y")
    end

    def period
      "#{date(@report.from)} a #{date(@report.to - 1.second)}"
    end

    def change(value)
      value.nil? ? "Sem base" : "#{value.positive? ? '+' : ''}#{value}%"
    end

    def duration(value)
      seconds = value.to_i
      "#{seconds / 3600}h #{seconds % 3600 / 60}min #{seconds % 60}s"
    end
  end
end
