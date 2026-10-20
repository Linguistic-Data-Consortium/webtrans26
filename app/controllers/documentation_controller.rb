# Browses the Markdown files in docs/. Slugs map 1:1 to filenames in
# docs/ (the slug is the basename without `.md`), so /documentation/USER_GUIDE
# renders docs/USER_GUIDE.md.
class DocumentationController < ApplicationController
  DOCS_DIR = Rails.root.join("docs")

  # Slugs are filename-safe ASCII; this prevents path traversal and
  # restricts to files that look like documentation pages.
  VALID_SLUG = /\A[A-Za-z0-9_\-]+\z/

  def index
    @docs = list_docs
  end

  def show
    slug = params[:slug].to_s
    raise ActionController::RoutingError, "invalid slug" unless slug.match?(VALID_SLUG)

    path = DOCS_DIR.join("#{slug}.md")
    raise ActionController::RoutingError, "doc not found" unless File.exist?(path)

    source = File.read(path)
    @slug = slug
    @title = extract_title(source) || slug.humanize
    # Strip the leading `# Heading` from the rendered body — we already
    # surface it as the page title in the show view, so rendering it again
    # in the article would duplicate it at the top.
    @html = render_markdown(strip_leading_title(source)).html_safe
    # Every doc, in the one order they always appear in — the sidebar marks
    # which is open rather than moving it. It used to be handed the others and
    # append the current one, which put whichever you were reading last in the
    # list, so the sidebar reshuffled as you moved between pages.
    @docs = list_docs
  end

  private

  def list_docs
    Dir.glob(DOCS_DIR.join("*.md")).filter_map do |path|
      slug = File.basename(path, ".md")
      next unless slug.match?(VALID_SLUG)
      { slug: slug, title: extract_title(File.read(path)) || slug.humanize }
    end.sort_by { |d| d[:title].downcase }
  end

  # First `# Heading` line in the file becomes the page title; falls back
  # to a humanized slug if the file doesn't start with one.
  def extract_title(source)
    source.each_line do |line|
      stripped = line.strip
      next if stripped.empty?
      if stripped.start_with?("# ")
        return stripped.sub(/\A#\s+/, "").strip
      end
      break
    end
    nil
  end

  # Drops the first non-blank line if it's an `# H1`. Leaves the rest of the
  # file intact (including any later `#` lines or content above the heading
  # like a stray comment).
  def strip_leading_title(source)
    lines = source.lines
    idx = lines.index { |line| !line.strip.empty? }
    return source unless idx
    return source unless lines[idx].strip.start_with?("# ")
    (lines[0...idx] + lines[(idx + 1)..]).join
  end

  def render_markdown(text)
    @renderer ||= Redcarpet::Markdown.new(
      Redcarpet::Render::HTML.new(hard_wrap: true, with_toc_data: true),
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      no_intra_emphasis: true,
      space_after_headers: true,
      superscript: true,
      underline: true
    )
    @renderer.render(text)
  end
end
