module Analytics
  class PdfReport
    PAGE_SIZE = 44

    def initialize(report)
      @report = report
    end

    def call
      pages = lines.each_slice(PAGE_SIZE).to_a
      objects = [nil, "<< /Type /Catalog /Pages 2 0 R >>", nil, "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>"]
      page_ids = []

      pages.each_with_index do |page_lines, index|
        page_id = 4 + (index * 2)
        stream_id = page_id + 1
        page_ids << page_id
        stream = content_stream(page_lines)
        objects[page_id] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents #{stream_id} 0 R >>"
        objects[stream_id] = "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream"
      end
      objects[2] = "<< /Type /Pages /Kids [#{page_ids.map { |id| "#{id} 0 R" }.join(" ")}] /Count #{page_ids.size} >>"
      build_pdf(objects)
    end

    private

    def lines
      summary = @report.summary
      previous = @report.summary(previous: true)
      result = ["CM HUB - INTELIGENCIA EDITORIAL", @report.site.name.to_s,
        "Analise: #{@report.label}",
        "Periodo UTC: #{@report.from.to_date} a #{(@report.to - 1).to_date}",
        "Anterior UTC: #{@report.previous_from.to_date} a #{(@report.from - 1).to_date}",
        "Filtros: #{@report.filters.to_json}", "",
        "Visualizacoes: #{summary[:views]} | Anterior: #{previous[:views]}",
        "Materias com acessos: #{summary[:articles]} | Cliques: #{summary[:clicks]}",
        "Identificadores de visitantes/dia: #{summary[:visitors]}",
        "Tempo registrado: #{summary[:engagement_seconds]} segundos", ""]
      @report.rows(limit: nil).each_with_index do |row, index|
        result << "#{index + 1}. #{row[:name]}"
        if @report.dimension == "articles"
          result << "ID: #{row[:key]} | #{row[:author]} | #{row[:category]}"
        end
        result << "Views: #{row[:views]} | Anterior: #{row[:previous_views]} | Variacao: #{row[:views_change].nil? ? 'Sem base' : "#{row[:views_change]}%"}"
        result << "Materias: #{row[:articles]} | Mediana: #{row[:median_views]} | Cliques: #{row[:clicks]}"
        result << "Tempo registrado: #{row[:engagement_seconds]}s | Identificadores/dia: #{row[:visitors]}"
        result << ""
      end
      result << "NOTAS DE MEDICAO"
      result.concat(@report.notes)
      # Fixed-width wrapping protects the printable area even for long titles/URLs.
      result.flat_map { |line| I18n.transliterate(line.to_s).scan(/.{1,75}(?:\s+|\z)|.{1,75}/).map(&:strip).presence || [""] }
    end

    def content_stream(page_lines)
      commands = ["BT", "/F1 10 Tf", "50 795 Td"]
      page_lines.each_with_index do |line, index|
        commands << "(#{escape(line)}) Tj"
        commands << "0 -17 Td"
      end
      commands << "ET"
      commands.join("\n")
    end

    def build_pdf(objects)
      pdf = +"%PDF-1.4\n"
      offsets = [0]
      (1...objects.length).each do |id|
        offsets[id] = pdf.bytesize
        pdf << "#{id} 0 obj\n#{objects[id]}\nendobj\n"
      end
      xref = pdf.bytesize
      pdf << "xref\n0 #{objects.length}\n0000000000 65535 f \n"
      offsets.drop(1).each { |offset| pdf << format("%010d 00000 n \n", offset) }
      pdf << "trailer\n<< /Size #{objects.length} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
      pdf
    end

    def escape(value)
      I18n.transliterate(value.to_s).encode("ASCII", invalid: :replace, undef: :replace, replace: "?")
        .gsub(/[\\()]/) { |character| "\\#{character}" }
    end

    def truncate(value, length)
      value.to_s.length > length ? "#{value.to_s.first(length - 3)}..." : value.to_s
    end
  end
end
