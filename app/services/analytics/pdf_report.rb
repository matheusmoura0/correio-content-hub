require "prawn"

module Analytics
  class PdfReport
    RED = "AD1119".freeze
    INK = "20242A".freeze
    MUTED = "68707C".freeze
    LINE = "E2E5E9".freeze
    FONT_ROOT = "/usr/share/fonts/truetype/dejavu".freeze
    SORT_LABELS = { "views" => "visualizações", "articles" => "conteúdos acessados",
      "clicks" => "cliques", "engagement_seconds" => "tempo registrado" }.freeze

    def initialize(report)
      @report = report
    end

    def call
      @rows = @report.rows(limit: nil)
      @pdf = Prawn::Document.new(page_size: "A4", margin: [94, 42, 52, 42],
        info: { Title: "#{@report.site.name} - Relatório de audiência", Author: "Correio da Manhã",
          Subject: "#{@report.label}: #{period}", Creator: "CM Content Hub" })
      @pdf.font_families.update("EditorialSans" => {
        normal: "#{FONT_ROOT}/DejaVuSans.ttf", bold: "#{FONT_ROOT}/DejaVuSans-Bold.ttf"
      }, "EditorialSerif" => { normal: "#{FONT_ROOT}/DejaVuSerif.ttf", bold: "#{FONT_ROOT}/DejaVuSerif-Bold.ttf" })
      @pdf.font "EditorialSans", size: 9
      @pdf.fill_color INK
      overview
      ranking
      measurement_notes
      chrome
      @pdf.render
    end

    private

    def overview
      @pdf.fill_color RED
      @pdf.text "INTELIGÊNCIA EDITORIAL", size: 9, style: :bold
      @pdf.move_down 9
      @pdf.fill_color INK
      @pdf.font("EditorialSerif") { @pdf.text "Relatório de audiência", size: 26, style: :bold }
      @pdf.move_down 8
      @pdf.text safe(@report.site.name), size: 12, style: :bold
      @pdf.text "#{period} · dias completos em UTC", color: MUTED, size: 9
      @pdf.move_down 6
      @pdf.text "Comparação: #{date(@report.previous_from)} a #{date(@report.from - 1.second)}", color: MUTED, size: 8
      @pdf.move_down 14
      @pdf.text "#{@report.label} · ordenação por #{SORT_LABELS.fetch(@report.sort)}", size: 10, style: :bold
      filter_labels = { q: "Busca", author: "Assinatura", category: "Editoria", article: "Matéria" }
      @report.filters.each do |key, value|
        label = value == Analytics::EditorialReport::MISSING ? "Não informado" : safe(value, 200)
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
      @pdf.text "#{number(@rows.length)} resultados no ranking completo. Tempo registrado: #{duration(summary[:engagement_seconds])}.", size: 8, color: MUTED
      @pdf.move_down 8
      @pdf.text "A contagem de visitantes soma identificadores diários; não representa pessoas únicas no período.", size: 8, color: MUTED
    end

    def daily_chart
      @pdf.text "Evolução diária de visualizações", size: 11, style: :bold
      @pdf.move_down 5
      @pdf.text "Vermelho: período atual · Cinza: período anterior equivalente", size: 7, color: MUTED
      @pdf.move_down 10
      daily = @report.daily_views
      prior = @report.daily_views(previous: true)
      peak = [daily.map { |day| day[:views] }.max.to_i, prior.map { |day| day[:views] }.max.to_i, 1].max
      width = @pdf.bounds.width
      @pdf.bounding_box([0, @pdf.cursor], width: width, height: 142) do
        step = width / [daily.length, 1].max
        daily.each_with_index do |day, index|
          [[prior[index]&.dig(:views).to_i, "C9CED4", 0.08], [day[:views], RED, 0.52]].each do |count, color, offset|
            next if count.zero?
            height = count * 112.0 / peak
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
        name = safe(row[:name], 600)
        detail = if @report.dimension == "articles"
          "#{safe(row[:author], 160)} · #{safe(row[:category], 100)}"
        else
          "#{number(row[:articles])} matérias · mediana #{row[:median_views]} · #{duration(row[:engagement_seconds])}"
        end
        cells = [number(index + 1), "#{name}\n#{detail}", number(row[:views]),
          number(row[:previous_views]), change(row[:views_change]), number(row[:clicks])]
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

    def ranking_heading
      @pdf.text "Ranking · #{@report.label}", size: 17, style: :bold
      @pdf.move_down 5
      @pdf.text "#{number(@rows.length)} resultados · #{period} · ordem por #{SORT_LABELS.fetch(@report.sort)}", size: 8, color: MUTED
      @pdf.move_down 14
      top = @pdf.cursor
      @pdf.fill_color INK
      @pdf.fill_rectangle [0, top], @pdf.bounds.width, 30
      @pdf.fill_color "FFFFFF"
      x = 0
      ["#", @report.dimension == "articles" ? "Matéria / assinatura" : "Nome / conteúdos", "Visualizações", "Anterior", "Variação", "Cliques"].each_with_index do |text, i|
        @pdf.text_box text, at: [x + 6, top - 10], width: widths[i] - 12, height: 18,
          size: 7, align: i > 1 ? :right : :left
        x += widths[i]
      end
      @pdf.fill_color INK
      @pdf.move_cursor_to top - 30
    end

    def measurement_notes
      @pdf.start_new_page if @pdf.cursor < 220
      @pdf.move_down 20
      @pdf.text "Notas de medição", size: 12, style: :bold
      @pdf.move_down 10
      @report.notes.each { |note| @pdf.text safe(note), size: 8, color: MUTED, leading: 3; @pdf.move_down 6 }
      @pdf.text "Títulos acima de 600 caracteres são abreviados neste documento. O ranking inclui todos os resultados filtrados, independentemente da paginação do painel.", size: 8, color: MUTED
      @pdf.move_down 6
      @pdf.text "Fonte: tag de audiência do #{@report.site.name}. Emitido em #{Time.current.strftime('%d/%m/%Y às %H:%M')} (Brasília).", size: 8, color: MUTED
    end

    def chrome
      @pdf.repeat(:all, dynamic: true) do
        @pdf.bounding_box([0, @pdf.bounds.top + 58], width: @pdf.bounds.width, height: 44) do
          @pdf.fill_color RED
          @pdf.fill_rectangle [0, 44], 36, 36
          @pdf.font("EditorialSerif") do
            @pdf.fill_color "FFFFFF"
            @pdf.text_box "CM", at: [2, 35], width: 32, align: :center, size: 15, style: :bold
            @pdf.fill_color INK
            @pdf.text_box safe(@report.site.name, 80), at: [48, 43], width: @pdf.bounds.width - 48, size: 18, style: :bold
          end
          @pdf.fill_color MUTED
          @pdf.text_box "RELATÓRIO DE AUDIÊNCIA · #{@report.label.upcase}", at: [48, 17], size: 7
        end
        @pdf.stroke_color LINE
        @pdf.stroke_horizontal_line 0, @pdf.bounds.width, at: -12
        @pdf.fill_color MUTED
        @pdf.text_box "Correio da Manhã · Audiência editorial", at: [0, -24], width: 300, height: 12, size: 7
      end
      @pdf.number_pages "Página <page> de <total>",
        at: [@pdf.bounds.width - 140, -24], width: 140, align: :right, size: 7, color: MUTED
    end

    def widths
      @widths ||= [0.065, 0.415, 0.14, 0.13, 0.12, 0.13].map { |part| @pdf.bounds.width * part }
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
