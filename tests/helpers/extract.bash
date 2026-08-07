# Pull fenced code blocks out of a SKILL.md so tests exercise the *actual*
# documented commands rather than a re-typed copy.

# extract_code_block <file> <heading-substring> <lang>
# Prints the first ```<lang> fenced block that appears at/after the first line
# containing <heading-substring>.
extract_code_block() {
  local file="$1" heading="$2" lang="$3"
  awk -v h="$heading" -v lang="$lang" '
    !found && index($0, h) { found = 1; next }
    found && !inblock && /^```/ {
      f = $0; sub(/^```/, "", f); gsub(/[[:space:]]/, "", f)
      if (lang == "" || f == lang) { inblock = 1 }
      next
    }
    inblock && /^```/ { exit }
    inblock { print }
  ' "$file"
}
