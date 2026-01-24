module.exports = grammar({
  name: "markdown_notes",

  rules: {
    source_file: ($) =>
      repeat(choice($.wikilink, $.mention, $.hashtag, $.text)),

    wikilink: ($) => seq("[[", $.link_text, "]]"),

    // Mention: @username with UTF-8 support (Latin extended, Cyrillic, etc.)
    mention: ($) => seq("@", $.mention_text),
    mention_text: () => /[a-zA-Z0-9_\u00C0-\u024F\u0400-\u04FF\u1E00-\u1EFF-]+/,

    // Hashtag: #tag (alphanumeric, underscore, hyphen)
    hashtag: ($) => seq("#", $.hashtag_text),
    hashtag_text: () => /[a-zA-Z0-9_-]+/,

    link_text: () => /[^\]]+/,

    // Text: matches non-special chars OR email addresses (to prevent @ in emails becoming mentions)
    text: () => /([^\[@#]|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})+/,
  },
});
