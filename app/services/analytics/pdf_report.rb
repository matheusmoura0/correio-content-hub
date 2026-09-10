module Analytics
  class PdfReport
    PAGE_SIZE = 44

    def initialize(report)
      @report = report
    end

    def call
      pages = lines.each_slice(PAGE_SIZE).to_a
      objects = [nil, "<< /Type /Catalog /Pages 2 0 R >>", nil, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
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
      result = [
        "CM HUB - RELATORIO DE AUDIENCIA",
        @report.site.name.to_s.upcase,
        "Periodo: #{@report.from.to_date.strftime('%d/%m/%Y')} a #{@report.to.to_date.strftime('%d/%m/%Y')}", "",
        "RESUMO",
        "Visualizacoes: #{summary[:views]}",
        "Visitantes unicos: #{summary[:visitors]}",
        "Cliques: #{summary[:clicks]}",
        "CTR: #{summary[:ctr]}%",
        "Tempo medio de leitura: #{summary[:average_engagement]} segundos", "",
        "PAGINAS MAIS VISTAS"
      ]
      @report.top_pages(limit: 20).each_with_index do |page, index|
        result << "#{index + 1}. #{truncate(page[:title], 72)} - #{page[:views]} views"
      end
      result << "" << "CLIQUES MAIS FREQUENTES"
      @report.top_clicks(limit: 12).each_with_index do |click, index|
        result << "#{index + 1}. #{truncate(click[:text], 68)} - #{click[:clicks]} cliques"
      end
      result << "" << "Gerado pelo Correio da Manha Content Hub em #{Time.current.strftime('%d/%m/%Y %H:%M')}"
      result
    end

    def content_stream(page_lines)
      commands = ["BT", "/F1 11 Tf", "50 795 Td"]
      page_lines.each_with_index do |line, index|
        commands << "/F1 #{index < 2 ? 16 : 11} Tf" if index < 2
        commands << "/F1 11 Tf" if index == 2
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
        .gsub("\\", "\\\\").gsub("(", "\\(").gsub(")", "\\)")
    end

    def truncate(value, length)
      value.to_s.length > length ? "#{value.to_s.first(length - 3)}..." : value.to_s
    end
  end
end
