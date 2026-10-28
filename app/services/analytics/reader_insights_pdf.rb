module Analytics
  module ReaderInsightsPdf
    private

    def reader_insight_pages
      insights = @report.reader_insights
      coverage, reading, groups = insights.coverage, insights.reading, insights.breakdowns
      @pdf.start_new_page
      reader_page_heading("Público · alcance e horários")
      @pdf.text "#{number(coverage[:known])} de #{number(coverage[:total])} visualizações com metadados (#{coverage[:percent]}%).", size: 9
      @pdf.move_down 4
      @pdf.text "#{number(coverage[:clicks])} cliques com metadados · somente tráfego da coleta recente.", size: 8, color: PdfReport::MUTED
      @pdf.move_down 12
      values = [["Leitura ativa mediana", reading[:active_seconds] && "#{reading[:active_seconds]}s"],
        ["Rolagem até 75%", reading[:scroll_75_percent] && "#{reading[:scroll_75_percent]}%"],
        ["Tempo até o clique", reading[:click_delay_seconds] && "#{reading[:click_delay_seconds]}s"]]
      width = @pdf.bounds.width / 3
      top = @pdf.cursor
      values.each_with_index do |(label, value), index|
        @pdf.fill_color PdfReport::MUTED
        @pdf.text_box label, at: [index * width, top], width: width - 10, height: 14, size: 8
        @pdf.fill_color PdfReport::INK
        @pdf.text_box value || "Sem amostra", at: [index * width, top - 19], width: width - 10, height: 25, size: value ? 19 : 11, style: :bold
      end
      @pdf.move_cursor_to top - 55
      reader_hour_chart(insights.hourly)
      reader_group_pair(["Países", groups[:countries]], ["Estados e regiões", groups[:regions]])
      reader_group_pair(["Cidades aproximadas", groups[:cities]], ["Fusos dos leitores", groups[:timezones]])
      @pdf.move_down 6
      insights.notes.first(4).each { |note| @pdf.text safe(note), size: 7, color: PdfReport::MUTED, leading: 1 }
      @pdf.move_down 4
      @pdf.formatted_text [{ text: "Localização aproximada por " }, { text: "DB-IP City Lite", link: "https://db-ip.com" }, { text: " · CC BY 4.0. VPNs e redes móveis podem alterar a estimativa." }], size: 7, color: PdfReport::MUTED

      @pdf.start_new_page
      reader_page_heading("Público · origens e comportamento")
      reader_group_pair(["Origens de tráfego", groups[:sources]], ["Campanhas", groups[:campaigns]])
      reader_group_pair(["Dispositivos", groups[:devices]], ["Navegadores", groups[:browsers]])
      reader_group_pair(["Sistemas operacionais", groups[:systems]], ["Onde acontecem os cliques", groups[:placements]], right_unit: "Cliques")
      @pdf.fill_color PdfReport::INK
      @pdf.text "Dados por hora · Brasília", size: 10, style: :bold
      @pdf.move_down 6
      top = @pdf.cursor
      insights.hourly.each_slice(6).with_index do |hours, column|
        x = column * @pdf.bounds.width / 4
        @pdf.fill_color PdfReport::MUTED
        @pdf.text_box "Hora · Visualizações / Cliques", at: [x, top], width: @pdf.bounds.width / 4 - 8, height: 13, size: 6
        hours.each_with_index do |row, index|
          value = "#{'%02d' % row[:hour]}h · #{row[:views].nil? ? 'restrito' : number(row[:views])} / #{row[:clicks].nil? ? 'restrito' : number(row[:clicks])}"
          @pdf.text_box value, at: [x, top - 14 - index * 12], width: @pdf.bounds.width / 4 - 8, height: 12, size: 7
        end
      end
      @pdf.move_cursor_to top - 92
      @pdf.text "Até 5 grupos por quadro; rótulos longos abreviados. Grupos com menos de #{ReaderInsights::MIN_READERS} identificadores diários ficam restritos. Ausência de dado não é audiência zero.", size: 7, color: PdfReport::MUTED
    end

    def reader_page_heading(title)
      @pdf.fill_color PdfReport::INK
      @pdf.text title, size: 19, style: :bold
      @pdf.move_down 6
      @pdf.text "#{period} · #{@report.partial? ? 'dia atual parcial' : 'período fechado'} · UTC", size: 8, color: PdfReport::MUTED
      @pdf.move_down 14
    end

    def reader_hour_chart(rows)
      @pdf.fill_color PdfReport::INK
      @pdf.text "Horários · vermelho: visualizações · verde: cliques", size: 8, style: :bold
      @pdf.move_down 6
      top, width = @pdf.cursor, @pdf.bounds.width
      peak = [rows.flat_map { |row| [row[:views].to_i, row[:clicks].to_i] }.max.to_i, 1].max
      step = width / 24
      rows.each_with_index do |row, index|
        [[row[:views], PdfReport::RED, 0.1], [row[:clicks], "16816B", 0.52]].each do |value, color, offset|
          next unless value.to_i.positive?
          height = value * 65.0 / peak
          @pdf.fill_color color
          @pdf.fill_rectangle [index * step + offset * step, top - 70 + height], step * 0.35, height
        end
      end
      @pdf.fill_color PdfReport::MUTED
      @pdf.text_box "00h                 06h                 12h                 18h                 23h · Brasília", at: [0, top - 77], width: width, height: 12, size: 7
      @pdf.move_cursor_to top - 98
    end

    def reader_group_pair(left, right, right_unit: "Visualizações")
      top = @pdf.cursor
      width = (@pdf.bounds.width - 22) / 2
      [[left, 0, "Visualizações"], [right, width + 22, right_unit]].each do |(title, rows), x, unit|
        @pdf.bounding_box([x, top], width: width, height: 145) do
          @pdf.fill_color PdfReport::INK
          @pdf.text_box title, at: [0, 145], width: width, height: 20, size: 10, style: :bold
          @pdf.fill_color PdfReport::MUTED
          @pdf.text_box unit, at: [0, 129], width: width, height: 12, size: 7
          rows.first(5).each_with_index do |row, index|
            y = 112 - index * 21
            @pdf.fill_color PdfReport::INK
            @pdf.text_box safe(row[:label], 48), at: [0, y], width: width - 42, height: 20, size: 7
            @pdf.text_box number(row[:count]), at: [width - 40, y], width: 40, height: 20, size: 8, align: :right
          end
          if rows.empty?
            @pdf.text_box "Sem amostra suficiente ou dado disponível.", at: [0, 110], width: width, height: 35, size: 8
          end
        end
      end
      @pdf.move_cursor_to top - 145
    end
  end
end
