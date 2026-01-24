# Completion Debug Session

## Problem
Tag (#) and mention (@) completions are not showing up, only wikilink completions work.

## Investigation

### Completion Patterns
All three types have the correct functions implemented:

**Wikilink** (`wikilink.lua:43-52`):
- `is_completion_match`: `line:match("%[%[$")` - triggers after `[[`
- `suggest`: Returns dummy items `wiki1`, `wiki2`

**Mentions** (`mentions.lua:44-53`):
- `is_completion_match`: `line:match("%@$")` - triggers after `@`
- `suggest`: Returns dummy items `mention1`, `mention2`

**Tags** (`tags.lua:122-131`):
- `is_completion_match`: `line:match("%#$")` - triggers after `#`
- `suggest`: Returns dummy items `tag1`, `tag2`

### Root Cause
**File**: `cmp_wikilinks_completion_source.lua:8-10`

```lua
function completion_source:get_trigger_characters()
  return { "[" }  -- ❌ Only [ is a trigger!
end
```

**Problem**: The completion source only registers `[` as a trigger character. When you type `@` or `#`, nvim-cmp doesn't know to trigger the completion source!

## Solution
Add `@` and `#` to the trigger characters array.

```lua
function completion_source:get_trigger_characters()
  return { "[", "@", "#" }
end
```

## Fix Applied
**File**: `cmp_wikilinks_completion_source.lua:8-10`

✅ Updated trigger characters to include `@` and `#`

## Testing
After restarting Neovim or reloading the plugin:
- [ ] Type `[[` - should show wiki1, wiki2
- [ ] Type `@` - should show mention1, mention2
- [ ] Type `#` - should show tag1, tag2

## Enhancement: Real File Completions for Mentions

### Change Made
**File**: `mentions.lua:48-67`

Updated `suggest()` to return actual filenames from `people_dir_path`:
```lua
M.suggest = function(cmp)
  -- Get all .md files from people directory
  local files = vim.fn.glob(M.opts.people_dir_path .. "/*.md", false, true)
  local items = {}

  for _, file_path in ipairs(files) do
    -- Remove path and .md extension
    local filename = vim.fn.fnamemodify(file_path, ":t:r")
    table.insert(items, {
      label = filename,
      kind = cmp.lsp.CompletionItemKind.Reference,
    })
  end

  return items
end
```

### Testing
Type `@` and you should see:
- ✅ All markdown files from `people_dir_path`
- ✅ Without `.md` extension
- ✅ Just the filename (no path)

## Enhancement: Recursive File Completions for Wikilinks

### Change Made
**File**: `wikilink.lua:47-69`

Updated `suggest()` to return all files recursively with relative paths:
```lua
M.suggest = function(cmp)
  -- Get all .md files recursively (**/*.md)
  local files = vim.fn.glob(M.opts.notes_root_path .. "/**/*.md", false, true)
  local items = {}

  for _, file_path in ipairs(files) do
    -- Get relative path from notes_root_path and remove .md
    local relative_path = vim.fn.fnamemodify(file_path, ":~:.")
      :gsub("^" .. vim.pesc(M.opts.notes_root_path .. "/"), "")
      :gsub("%.md$", "")

    table.insert(items, {
      label = relative_path,
      kind = cmp.lsp.CompletionItemKind.Reference,
    })
  end

  return items
end
```

### Examples
Type `[[` and you should see:
- ✅ `top-level-note` (file in root)
- ✅ `journal/2024-11-11` (file in subdirectory)
- ✅ `projects/foo/bar` (nested subdirectories)
- ✅ All paths relative to `notes_root_path`
- ✅ Without `.md` extension

## Fix: Hashtag Search Matching Full Tags Only

### Problem
When searching for `#neko`, it was also matching `#nekohealth` because of substring matching.

### Solution
**File**: `tags.lua:43-51`

Match tag followed by non-tag character or end of line:
```lua
-- Match tag followed by non-tag character or end of line
-- Tag characters are: [a-zA-Z0-9_-]
local pattern = '#' .. tag_text .. '([^a-zA-Z0-9_-]|$)'
{ 'rg', '--vimgrep', '-e', pattern, M.opts.notes_root_path }
```

### How it works
- `#neko([^a-zA-Z0-9_-]|$)` ✅ matches `#neko is cool`
- `#neko([^a-zA-Z0-9_-]|$)` ✅ matches `#neko.` and `#neko,`
- `#neko([^a-zA-Z0-9_-]|$)` ❌ does NOT match `#nekohealth`
- `#neko([^a-zA-Z0-9_-]|$)` ❌ does NOT match `#neko-fika` (hyphen is valid in tags)

**Evolution of the fix:**
1. ❌ Negative lookahead `(?![a-zA-Z0-9_-])` - requires PCRE2
2. ❌ Word boundary `\b` - treats hyphen as word separator (but hyphen is valid in tags)
3. ✅ Character class `([^a-zA-Z0-9_-]|$)` - matches complete tags including hyphens
