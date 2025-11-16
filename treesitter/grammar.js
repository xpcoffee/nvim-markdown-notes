module.exports = grammar({
  name: "markdown_notes",

  rules: {
    source_file: ($) => repeat(choice($.wikilink, $.text)),

    wikilink: ($) => seq("[[", $.link_text, "]]"),

    link_text: () => /[^\]]+/,

    // Match any character that's not [
    text: () => /[^\[]+/,
  },
});
