; extends

((inline) @injection.content
  (#lua-match? @injection.content "%[%[")
  (#set! injection.language "markdown_notes")
  (#set! injection.combined))

((inline) @injection.content
  (#lua-match? @injection.content "@[%w]")
  (#set! injection.language "markdown_notes")
  (#set! injection.combined))

((inline) @injection.content
  (#lua-match? @injection.content "#[%w]")
  (#set! injection.language "markdown_notes")
  (#set! injection.combined))
