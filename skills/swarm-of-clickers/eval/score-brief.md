# Scorer brief

You score one run of clickers against an answer key. You read text files only. You never open the fixture app, a browser or any screenshot, and you never guess which model or arm wrote the notes. You never dispatch agents.

Your dispatch prompt gave you: the answer key path, the input path, and the path to write the CSV to.

## Input

- The key: `answer-key.md`, a table `id | category | page | element | description` with ids K01 to K20. Read the table only; skip the "Expected check hits" section.
- The entries to score, from one of:
  - a run directory: every `<run>/clickers/*/notes.json` is a list of entries `{"kind_guess", "title", "page", "width", "steps", "evidence", "source", "shots"}`. An entry's id is `<clicker dir>:<0-based index>`, where the clicker dir is the name of the directory holding that `notes.json`, and the index is the entry's position in its list.
  - a single `findings.json` (the caller's merged set): `{"run": {...}, "findings": [{"id", "title", "kind", "page", "width", "steps", "evidence", "seen_by", "source", "fix", "shots"}]}`. An entry's id is its `id` field.

## Matching

Read each entry's title, page, steps and evidence. It matches a key id when it names the same element and the same problem as that row's description. The page must agree too, unless the key row lists two pages. Judge by what the entry says it saw, not by its guess at a category.

- An entry matches at most one key id: the closest one.
- A vague entry ("the page looks off", "spacing is inconsistent") that does not point at one key row's element is `false`. So is an entry about the right element with the wrong problem, and an entry about something the key does not list.
- Several entries may match the same key id (two clickers found it, or one noted it twice). Write each of them with that key id. Do not mark the later ones `false`: they are duplicates, neither extra recall nor false findings.
- Do not give credit for an entry you can only match by reading more into it than it says.

## Output

Write a CSV to the output path, one row per entry, in input order (clicker dirs sorted by name), with this header and no quoting needed (ids contain no commas):

    id,matched_key,category

`matched_key` is the key id, or `false`. `category` is that key row's category (`measurable`, `visual`, `UX` or `functional`), or `false`.

Then return only one line: the number of distinct key ids matched per category out of that category's count in the key, then the false count. For example, with invented numbers:

    measurable 3/6, visual 2/6, UX 1/4, functional 2/4, false 5

Count distinct ids, so a duplicate adds nothing. Return nothing else: no list, no reasons, no guess at who wrote the notes.
