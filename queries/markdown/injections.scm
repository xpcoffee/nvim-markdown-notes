; extends

((inline) @injection.content
  (#match? @injection.content "\\[\\[")
  (#set! injection.language "markdown_notes")
  (#set! injection.combined))
