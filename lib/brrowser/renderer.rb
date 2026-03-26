require 'nokogiri'

module Brrowser
  class Renderer
    SKIP_ELEMENTS = %w[script style noscript svg head].freeze
    BLOCK_ELEMENTS = %w[
      p div section article aside main header footer nav
      h1 h2 h3 h4 h5 h6 ul ol li dl dt dd
      blockquote pre figure figcaption address
      table thead tbody tfoot tr
      form fieldset details summary hr br
    ].freeze

    IMG_RESERVE = 10  # Blank lines reserved for each image

    attr_reader :links, :images

    def initialize(width)
      @width    = width
      @links    = []
      @images   = []
      @output   = []
      @line     = ""
      @col      = 0
      @indent   = 0
      @pre      = false
      @ol_count = []
    end

    def render(html, base_url = nil)
      @base_url = base_url
      @links    = []
      @images   = []
      @output   = []
      @line     = ""
      @col      = 0

      doc = Nokogiri::HTML(html)
      title = doc.at_css("title")&.text&.strip || ""

      body = doc.at_css("body") || doc
      walk(body)
      flush_line

      { text: @output.join("\n"), links: @links, images: @images, title: title }
    end

    private

    def walk(node)
      node.children.each { |child| process(child) }
    end

    def process(node)
      if node.text?
        handle_text(node.text)
      elsif node.element?
        handle_element(node)
      end
    end

    def handle_text(text)
      if @pre
        text.each_line do |line|
          @line << line.chomp.fg(186)
          if line.end_with?("\n")
            flush_line
          end
        end
      else
        text = text.gsub(/\s+/, " ")
        return if text == " " && @col == 0
        words = text.split(/( )/)
        words.each do |word|
          next if word.empty?
          visible = word.gsub(/\e\[[0-9;]*m/, "")
          if @col + visible.length > @width && @col > 0 && word != " "
            flush_line
          end
          @line << apply_style(word)
          @col += visible.length
        end
      end
    end

    def handle_element(node)
      tag = node.name.downcase
      return if SKIP_ELEMENTS.include?(tag)

      case tag
      when "br"
        flush_line
      when "hr"
        ensure_blank_line
        @line << ("─" * @width).fg(240)
        flush_line
        ensure_blank_line
      when "h1"
        ensure_blank_line
        text = collect_text(node)
        @line << text.b.fg(220)
        flush_line
        @line << ("═" * [text.gsub(/\e\[[0-9;]*m/, "").length, @width].min).fg(220)
        flush_line
        ensure_blank_line
      when "h2"
        ensure_blank_line
        inline_walk(node, :b, 214)
        flush_line
        ensure_blank_line
      when "h3"
        ensure_blank_line
        inline_walk(node, :b, 208)
        flush_line
        ensure_blank_line
      when "h4", "h5", "h6"
        ensure_blank_line
        inline_walk(node, :b, 252)
        flush_line
        ensure_blank_line
      when "p", "div", "section", "article", "aside", "main",
           "header", "footer", "nav", "address", "figure", "figcaption",
           "details", "summary"
        ensure_blank_line
        walk(node)
        flush_line
        ensure_blank_line
      when "blockquote"
        ensure_blank_line
        old_indent = @indent
        @indent += 2
        walk(node)
        flush_line
        @indent = old_indent
        ensure_blank_line
      when "pre"
        ensure_blank_line
        @pre = true
        walk(node)
        flush_line
        @pre = false
        ensure_blank_line
      when "code"
        if @pre
          walk(node)
        else
          text = collect_text(node)
          @line << text.fg(186)
          @col += text.length
        end
      when "ul"
        ensure_blank_line
        old_indent = @indent
        @indent += 2
        walk(node)
        flush_line
        @indent = old_indent
      when "ol"
        ensure_blank_line
        old_indent = @indent
        @indent += 2
        @ol_count.push(0)
        walk(node)
        flush_line
        @ol_count.pop
        @indent = old_indent
      when "li"
        flush_line if @col > 0
        if !@ol_count.empty?
          @ol_count[-1] += 1
          prefix = "#{@ol_count[-1]}. "
        else
          prefix = "\u2022 "
        end
        @line << prefix.fg(245)
        @col += prefix.length
        walk(node)
        flush_line
      when "dl"
        ensure_blank_line
        walk(node)
        ensure_blank_line
      when "dt"
        flush_line if @col > 0
        inline_walk(node, :b, 252)
        flush_line
      when "dd"
        old_indent = @indent
        @indent += 4
        walk(node)
        flush_line
        @indent = old_indent
      when "a"
        href = node["href"]
        text = collect_text(node)
        has_img = node.at_css("img")
        return if text.strip.empty? && !has_img

        if href && !href.start_with?("#", "javascript:")
          href = resolve_url(href)
          link_index = @links.length
          link_line = @output.length
          @links << { index: link_index, href: href, text: text.strip, line: link_line }
          if has_img
            # Walk children so <img> elements get processed
            @in_link = link_index
            walk(node)
            @in_link = nil
          else
            @line << text.fg(81).u
            @col += text.length
          end
          label = "[#{link_index}]"
          @line << label.fg(39)
          @col += label.length
        else
          if has_img
            walk(node)
          else
            @line << text.fg(81)
            @col += text.length
          end
        end
      when "strong", "b"
        inline_walk(node, :b)
      when "em", "i"
        inline_walk(node, :i)
      when "u"
        inline_walk(node, :u)
      when "s", "strike", "del"
        text = collect_text(node)
        @line << text.fg(240)
        @col += text.length
      when "img"
        alt = node["alt"] || "image"
        src = node["src"] || node["data-src"] || ""
        src = src.strip
        if !src.empty?
          src = resolve_url(src)
          flush_line if @col > 0
          line_num = @output.length
          @images << { src: src, alt: alt, line: line_num, height: IMG_RESERVE }
          @output << "[image]".fg(236)
          (IMG_RESERVE - 1).times { @output << "" }
        end
      when "iframe"
        src = node["src"] || ""
        src = resolve_url(src) unless src.empty?
        if src.match?(%r{youtube\.com/embed/|youtube-nocookie\.com/embed/})
          video_id = src[%r{/embed/([^?&/]+)}, 1]
          if video_id
            ensure_blank_line
            # Add YouTube thumbnail as image
            thumb_url = "https://img.youtube.com/vi/#{video_id}/hqdefault.jpg"
            flush_line if @col > 0
            line_num = @output.length
            @images << { src: thumb_url, alt: "YouTube video", line: line_num, height: IMG_RESERVE }
            @output << "[YouTube video]".fg(236)
            (IMG_RESERVE - 1).times { @output << "" }
            # Add link to video
            video_url = "https://www.youtube.com/watch?v=#{video_id}"
            link_index = @links.length
            link_line = @output.length
            @links << { index: link_index, href: video_url, text: "Watch on YouTube", line: link_line }
            @line << "\u25b6 Watch on YouTube".fg(196).b + "[#{link_index}]".fg(39)
            @col += 19 + "[#{link_index}]".length
            flush_line
            ensure_blank_line
          end
        elsif !src.empty?
          ensure_blank_line
          link_index = @links.length
          link_line = @output.length
          @links << { index: link_index, href: src, text: "Embedded content", line: link_line }
          @line << "[Embedded: #{src[0..50]}]".fg(245) + "[#{link_index}]".fg(39)
          @col += 63 + "[#{link_index}]".length
          flush_line
          ensure_blank_line
        end
      when "table"
        render_table(node)
      when "form"
        ensure_blank_line
        @line << "[Form]".fg(208).b
        flush_line
        walk(node)
        ensure_blank_line
      when "input"
        type = node["type"] || "text"
        name = node["name"] || ""
        value = node["value"] || ""
        case type
        when "submit", "button"
          label = value.empty? ? "Submit" : value
          @line << " [#{label}] ".fg(0).bg(252)
          @col += label.length + 4
        when "hidden"
          # skip
        else
          placeholder = node["placeholder"] || name
          field = "[#{placeholder}: ________]".fg(252)
          @line << field
          @col += placeholder.length + 14
        end
      when "select"
        name = node["name"] || "select"
        @line << "[#{name} v]".fg(252)
        @col += name.length + 4
      when "textarea"
        name = node["name"] || "text"
        @line << "[#{name}: ________]".fg(252)
        @col += name.length + 14
      when "label"
        walk(node)
      when "span"
        walk(node)
      else
        walk(node)
      end
    end

    def inline_walk(node, style = nil, color = nil)
      text = collect_text(node)
      styled = text
      styled = styled.send(style) if style
      styled = styled.fg(color) if color
      @line << styled
      @col += text.length
    end

    def collect_text(node)
      node.text.gsub(/\s+/, " ").strip
    end

    def flush_line
      return if @line.empty? && @col == 0
      prefix = " " * @indent
      if @pre
        prefix += "  "
      end
      @output << prefix + @line
      @line = ""
      @col  = 0
    end

    def ensure_blank_line
      flush_line if @col > 0
      @output << "" unless @output.empty? || @output.last == ""
    end

    def apply_style(text)
      text
    end

    def resolve_url(href)
      return "https:#{href}" if href.start_with?("//")
      return href if href.match?(%r{^https?://})
      return href unless @base_url
      begin
        URI.join(@base_url, href).to_s
      rescue
        href
      end
    end

    def render_table(table_node)
      ensure_blank_line
      rows = []

      table_node.css("tr").each do |tr|
        cells = tr.css("th, td").map { |cell| collect_text(cell) }
        rows << cells
      end

      return if rows.empty?

      max_cols = rows.map(&:length).max
      rows.each { |r| r.fill("", r.length...max_cols) }

      col_widths = Array.new(max_cols, 0)
      rows.each do |row|
        row.each_with_index do |cell, i|
          col_widths[i] = [col_widths[i], cell.length].max
        end
      end

      available = @width - @indent - (max_cols - 1) * 3
      total = col_widths.sum
      if total > available && total > 0
        col_widths = col_widths.map { |w| [(w.to_f / total * available).floor, 4].max }
      end

      rows.each_with_index do |row, ri|
        parts = row.each_with_index.map do |cell, ci|
          w = col_widths[ci] || cell.length
          cell.length > w ? cell[0...w] : cell.ljust(w)
        end
        line = parts.join(" \u2502 ".fg(240))
        if ri == 0 && table_node.at_css("th")
          line = line.b
        end
        @output << (" " * @indent) + line

        if ri == 0 && table_node.at_css("th")
          sep = col_widths.map { |w| "\u2500" * w }.join("\u2500\u253c\u2500").fg(240)
          @output << (" " * @indent) + sep
        end
      end

      ensure_blank_line
    end
  end
end
