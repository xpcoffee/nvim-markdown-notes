module.exports = grammar({
  name: "markdown_notes",

  // Disable implicit whitespace between tokens to prevent mentions/hashtags
  // from spanning across lines (e.g. @\nalice being parsed as @alice)
  extras: () => [],

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

    // Text: matches non-special chars, email addresses (to prevent @ in emails becoming mentions),
    // or @/# followed by whitespace (e.g. "# heading", "@ alone")
    text: () => /([^\[@#]|\[[^\[]|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|[@#][\s])+/,
  },
});
