.PHONY: all clean parser test

# Detect OS
UNAME_S := $(shell uname -s)

# Compiler and flags
CC := cc
CFLAGS := -O3 -Wall -Wextra -I./treesitter/src -fPIC

# Output paths
PARSER_DIR := parser
GRAMMAR_DIR := treesitter
SRC_DIR := $(GRAMMAR_DIR)/src

# Parser output name
ifeq ($(UNAME_S),Linux)
	PARSER_EXT := so
	LDFLAGS := -shared
endif
ifeq ($(UNAME_S),Darwin)
	PARSER_EXT := so
	LDFLAGS := -shared -undefined dynamic_lookup
endif
ifeq ($(OS),Windows_NT)
	PARSER_EXT := dll
	LDFLAGS := -shared
endif

PARSER_OUT := $(PARSER_DIR)/markdown_notes.$(PARSER_EXT)

# Default target
all: parser

# Generate parser from grammar.js
generate:
	@echo "Generating parser from grammar.js..."
	@cd $(GRAMMAR_DIR) && tree-sitter generate
	@echo "Parser source generated in $(SRC_DIR)"

# Compile parser to shared library
parser: generate
	@echo "Compiling parser..."
	@mkdir -p $(PARSER_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(PARSER_OUT) $(SRC_DIR)/parser.c
	@echo "Parser compiled to $(PARSER_OUT)"

# Test the grammar
test:
	@echo "Testing grammar..."
	@cd $(GRAMMAR_DIR) && echo "[[test link]]" | tree-sitter parse

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	@rm -rf $(SRC_DIR)
	@rm -f $(PARSER_OUT)
	@rm -f $(GRAMMAR_DIR)/grammar.json
	@echo "Clean complete"

# Check if tree-sitter CLI is installed
check:
	@which tree-sitter > /dev/null || (echo "Error: tree-sitter CLI not found. Install with: npm install -g tree-sitter-cli" && exit 1)
	@echo "tree-sitter CLI found: $$(tree-sitter --version)"
