# Tests

Containerized [bats](https://github.com/bats-core/bats-core) suite for the
shell scripts (`sync.sh`, `claude/statusline-command.sh`) and the executable
command blocks documented in the skills.

The repo is mounted **read-only** and every test runs against a throwaway
`$HOME`, so the suite never touches your real `~/.claude`.

```sh
tests/run.sh          # whole suite
```

Requires Docker. The image pins `bash`, `bats`, `jq`, `git`, and `gawk`.
