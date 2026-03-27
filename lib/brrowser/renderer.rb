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

    attr_reader :links, :images, :forms

    def initialize(width)
      @width    = width
      @links    = []
      @images   = []
      @forms    = []
      @output   = []
      @line     = ""
      @col      = 0
      @indent   = 0
      @pre      = false
      @ol_count = []
      @current_form = nil
    end

    def render(html, base_url = nil)
      @base_url = base_url
      @links    = []
      @images   = []
      @forms    = []
      @output   = []
      @line     = ""
      @col      = 0

      doc = Nokogiri::HTML(html)
      title = doc.at_css("title")&.text&.strip || ""

      body = doc.at_css("body") || doc
      walk(body)
      flush_line

      site_colors = extract_site_colors(doc)
      { text: @output.join("\n"), links: @links, images: @images, forms: @forms, title: title, colors: site_colors }
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
        action = node["action"] || ""
        action = resolve_url(action) unless action.empty?
        method = (node["method"] || "get").downcase
        @current_form = { action: action, method: method, fields: [], line: @output.length }
        @line << "[Form]".fg(208).b
        flush_line
        walk(node)
        # Check if form has password field
        has_pw = @current_form[:fields].any? { |f| f[:type] == "password" }
        @current_form[:has_password] = has_pw
        @forms << @current_form
        @current_form = nil
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
          @current_form[:fields] << { type: "submit", name: name, value: value } if @current_form
        when "hidden"
          @current_form[:fields] << { type: "hidden", name: name, value: value } if @current_form
        else
          placeholder = node["placeholder"] || name
          display_type = type == "password" ? "\u2022" : ""
          label = "#{placeholder}#{display_type}"
          field = "[#{label}: ________]".fg(252)
          @line << field
          @col += label.length + 14
          @current_form[:fields] << { type: type, name: name, value: value, placeholder: placeholder } if @current_form
        end
      when "select"
        name = node["name"] || "select"
        @line << "[#{name} v]".fg(252)
        @col += name.length + 4
        options = node.css("option").map { |o| { value: o["value"] || o.text, text: o.text.strip } }
        selected = node.at_css("option[selected]")
        val = selected ? (selected["value"] || selected.text) : options.first&.dig(:value)
        @current_form[:fields] << { type: "select", name: name, value: val.to_s, options: options } if @current_form
      when "textarea"
        name = node["name"] || "text"
        @line << "[#{name}: ________]".fg(252)
        @col += name.length + 14
        @current_form[:fields] << { type: "textarea", name: name, value: node.text } if @current_form
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

      # For very wide tables (too many columns), use vertical layout
      available = @width - @indent
      if max_cols > (available / 8)
        render_table_vertical(rows, table_node)
        return
      end

      col_widths = Array.new(max_cols, 0)
      rows.each do |row|
        row.each_with_index do |cell, i|
          col_widths[i] = [col_widths[i], cell.length].max
        end
      end

      space = available - (max_cols - 1) * 3
      total = col_widths.sum
      if total > space && total > 0
        col_widths = col_widths.map { |w| [(w.to_f / total * space).floor, 6].max }
      end

      rows.each_with_index do |row, ri|
        parts = row.each_with_index.map do |cell, ci|
          w = col_widths[ci] || cell.length
          cell.length > w ? cell[0...w] : cell.ljust(w)
        end
        line = parts.join(" \u2502 ".fg(240))
        line = line.b if ri == 0 && table_node.at_css("th")
        @output << (" " * @indent) + line

        if ri == 0 && table_node.at_css("th")
          sep = col_widths.map { |w| "\u2500" * w }.join("\u2500\u253c\u2500").fg(240)
          @output << (" " * @indent) + sep
        end
      end

      ensure_blank_line
    end

    def render_table_vertical(rows, table_node)
      headers = table_node.css("th").any? ? rows.shift : nil
      rows.each do |row|
        row.each_with_index do |cell, ci|
          next if cell.strip.empty?
          label = headers && headers[ci] ? headers[ci] : "Col #{ci + 1}"
          @output << (" " * @indent) + "#{label}: ".fg(245).b + cell
        end
        @output << (" " * @indent) + ("\u2500" * 20).fg(240)
      end
    end

    # Site color extraction {{{
    def extract_site_colors(doc)
      bg = nil; fg = nil

      # 1. HTML attributes (old-school)
      body = doc.at_css("body")
      if body
        bg = parse_css_color(body["bgcolor"]) if body["bgcolor"]
        fg = parse_css_color(body["text"]) if body["text"]
      end

      # 2. Inline styles on body/html
      [body, doc.at_css("html")].compact.each do |node|
        style = node["style"].to_s
        next if style.empty?
        bg ||= extract_css_color(style, /background(?:-color)?\s*:\s*([^;]+)/)
        fg ||= extract_css_color(style, /(?<!background-)color\s*:\s*([^;]+)/)
      end

      # 3. Embedded <style> blocks - check body, html, :root rules
      unless bg && fg
        doc.css("style").each do |style_node|
          css = style_node.text
          %w[body html :root .page .site .wrapper #page #wrapper #content].each do |sel|
            pattern = /#{Regexp.escape(sel)}\s*\{([^}]+)\}/m
            if css.match(pattern)
              block = $1
              bg ||= extract_css_color(block, /background(?:-color)?\s*:\s*([^;]+)/)
              fg ||= extract_css_color(block, /(?<!background-)color\s*:\s*([^;]+)/)
            end
          end
          # CSS variables: --bg-color, --background, --text-color, etc.
          css.scan(/--(bg|background|main-bg|site-bg|page-bg)[^:]*:\s*([^;}\n]+)/) do |_, val|
            bg ||= parse_css_color(val.strip)
          end
          css.scan(/--(fg|text|color|main-color|text-color|font-color)[^:]*:\s*([^;}\n]+)/) do |_, val|
            fg ||= parse_css_color(val.strip)
          end
        end
      end

      # 4. Meta theme-color
      unless bg
        meta = doc.at_css('meta[name="theme-color"]')
        bg = parse_css_color(meta["content"]) if meta && meta["content"]
      end

      { bg: bg, fg: fg }
    end

    def extract_css_color(css_text, regex)
      return nil unless css_text.match?(regex)
      val = css_text[regex, 1]&.strip
      parse_css_color(val)
    end

    def parse_css_color(val)
      return nil unless val
      val = val.strip.downcase

      # Hex colors
      if val.match?(/^#[0-9a-f]{6}$/)
        return hex_to_256(val)
      elsif val.match?(/^#[0-9a-f]{3}$/)
        expanded = "##{val[1]*2}#{val[2]*2}#{val[3]*2}"
        return hex_to_256(expanded)
      end

      # rgb(r, g, b)
      if val.match(/rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/)
        r, g, b = $1.to_i, $2.to_i, $3.to_i
        return rgb_to_256(r, g, b)
      end

      # Named colors (common ones)
      named = {
        "white" => 15, "black" => 0, "red" => 1, "green" => 2,
        "blue" => 4, "yellow" => 3, "cyan" => 6, "magenta" => 5,
        "gray" => 245, "grey" => 245, "silver" => 250,
        "darkgray" => 238, "darkgrey" => 238,
        "lightgray" => 252, "lightgrey" => 252,
        "navy" => 17, "teal" => 30, "maroon" => 1,
        "olive" => 3, "purple" => 5, "aqua" => 14,
        "orange" => 208, "pink" => 218,
        "whitesmoke" => 255, "ghostwhite" => 255,
        "aliceblue" => 153, "ivory" => 255,
      }
      named[val.gsub(/\s/, "")]
    end

    def hex_to_256(hex)
      r = hex[1..2].to_i(16)
      g = hex[3..4].to_i(16)
      b = hex[5..6].to_i(16)
      rgb_to_256(r, g, b)
    end

    def rgb_to_256(r, g, b)
      # Check grayscale ramp (232-255) first
      if r == g && g == b
        return 16 if r < 8
        return 231 if r > 248
        return (((r - 8).to_f / 247 * 24).round + 232)
      end
      # Map to 6x6x6 color cube (16-231)
      ri = ((r.to_f / 255) * 5).round
      gi = ((g.to_f / 255) * 5).round
      bi = ((b.to_f / 255) * 5).round
      16 + (36 * ri) + (6 * gi) + bi
    end
    # }}}
  end
end
