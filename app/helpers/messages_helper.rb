module MessagesHelper
  MARKDOWN_TAGS = %w[p br strong em del a ul ol li blockquote code pre h1 h2 h3 h4 hr].freeze
  MARKDOWN_ATTRIBUTES = %w[href title].freeze

  def render_message_markdown(body)
    html = Commonmarker.to_html(body.to_s, options: { render: { unsafe: false } })
    sanitize(html, tags: MARKDOWN_TAGS, attributes: MARKDOWN_ATTRIBUTES)
  end
end
