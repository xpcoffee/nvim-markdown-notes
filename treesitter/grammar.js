module.exports = grammar({
  name: "markdown_notes",

  rules: {
    source_file: ($) =>
      repeat(choice($.wikilink, $.mention, $.hashtag, $.text)),

    wikilink: ($) => seq("[[", $.link_text, "]]"),

    // Mention: @username (alphanumeric, underscore, hyphen)
    mention: ($) => seq("@", $.mention_text),
    mention_text: () => /[a-zA-Z0-9_-]+/,

    // Hashtag: #tag (alphanumeric, underscore, hyphen)
    hashtag: ($) => seq("#", $.hashtag_text),
    hashtag_text: () => /[a-zA-Z0-9_-]+/,

    link_text: () => /[^\]]+/,

    // Match any character that's not [
    text: () => /[^\[]+/,
  },
});
