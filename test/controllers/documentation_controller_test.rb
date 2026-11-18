require "test_helper"

# /documentation renders the Markdown in docs/. The sidebar lists every doc in
# one order, whichever one is open — it used to be handed the *others* and
# append the current one, so the page you were reading moved to the bottom and
# the list reshuffled as you moved around.
class DocumentationControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)   # the docs are behind sign-in
  end

  def titles_in_sidebar
    # The sidebar's items, in the order they render, current one included.
    @response.body.scan(%r{<li>\s*(?:<span class='current'>|<a[^>]*>)([^<]+)</}).flatten
  end

  test "the index lists every doc in docs/" do
    get documentation_index_url

    assert_response :success
    slugs = Dir.glob(Rails.root.join("docs", "*.md")).map { |p| File.basename(p, ".md") }
    slugs.each { |slug| assert_match documentation_show_path(slug), @response.body }
  end

  test "a doc renders, with its title as the heading" do
    get documentation_show_url("USER_GUIDE")

    assert_response :success
    assert_select "h1", text: "User Guide"
    assert_select ".doc-article"
  end

  test "the sidebar is in the same order whichever doc is open" do
    order = %w[ USER_GUIDE GETTING_STARTED KEYBINDINGS ].map do |slug|
      get documentation_show_url(slug)
      assert_response :success
      titles_in_sidebar
    end

    assert order.first.size > 3, "the sidebar lists the docs, not just 'All docs'"
    assert_equal order.first, order[1]
    assert_equal order.first, order[2]
  end

  test "the doc being read is in that order, not moved to the end" do
    get documentation_show_url("GETTING_STARTED")

    titles = titles_in_sidebar
    assert_includes titles, "Getting started — your first transcription, end to end"
    assert_not_equal titles.last, "Getting started — your first transcription, end to end",
      "it sits where it always sits"
    # And it's the one marked as current, rather than a link to itself.
    assert_select "li span.current", text: /Getting started/
  end

  test "every doc appears exactly once" do
    get documentation_show_url("USER_GUIDE")

    titles = titles_in_sidebar - [ "All docs" ]
    assert_equal titles.uniq.size, titles.size
    assert_equal Dir.glob(Rails.root.join("docs", "*.md")).size, titles.size
  end

  test "a slug that isn't a doc is a 404, not a stack trace" do
    get documentation_show_url("NOT_A_DOC")

    assert_response :not_found
  end

  # ── links between and within docs ──────────────────────────────────────────

  def article_hrefs(slug)
    get documentation_show_url(slug)
    assert_response :success
    Nokogiri::HTML(@response.body).css(".doc-article a[href]").map { |a| a["href"] }
  end

  def ids_on(slug)
    get documentation_show_url(slug)
    Nokogiri::HTML(@response.body).css("[id]").map { |e| e["id"] }
  end

  test "a link to another doc goes to that doc's page, not to its .md file" do
    hrefs = article_hrefs("USER_GUIDE")

    assert_includes hrefs, "/documentation/CONFIGURATION#per-project-s3"
    assert hrefs.none? { |h| h.match?(/\A[A-Za-z0-9_-]+\.md(#|\z)/) },
      "a doc still links to a bare .md file: #{hrefs.grep(/\.md/).inspect}"
  end

  test "a .md link that names no doc is left as it was" do
    controller = DocumentationController.new
    html = %(<a href="NOT_A_DOC.md#x">x</a> <a href="USER_GUIDE.md">u</a>)

    assert_equal %(<a href="NOT_A_DOC.md#x">x</a> <a href="/documentation/USER_GUIDE">u</a>),
                 controller.send(:link_docs, html)
  end

  # Every link the docs make to themselves, followed: the page has to exist and,
  # if the link names a heading, that heading has to be on it. The renderer's
  # heading ids are not GitHub's, so an anchor that works on GitHub can still
  # land at the top of the page here.
  test "every link between and within the docs reaches its target" do
    slugs = Dir.glob(Rails.root.join("docs", "*.md")).map { |p| File.basename(p, ".md") }
    ids = {}
    broken = []
    slugs.each do |slug|
      article_hrefs(slug).each do |href|
        target, anchor =
          case href
          when %r{\A/documentation/([A-Za-z0-9_-]+)(?:#(.*))?\z} then [ $1, $2 ]
          when /\A#(.*)\z/ then [ slug, $1 ]
          when /\A[A-Za-z0-9_-]+\.md(#|\z)/
            broken << "#{slug}: #{href} (a file path; the viewer has no route for it)"
            next
          else next
          end
        unless slugs.include?(target)
          broken << "#{slug}: #{href} (no such doc)"
          next
        end
        next if anchor.blank?
        ids[target] ||= ids_on(target)
        broken << "#{slug}: #{href} (no such heading)" unless ids[target].include?(anchor)
      end
    end

    assert_empty broken
  end
end
