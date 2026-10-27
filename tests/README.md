# Tests

Containerized [bats](https://github.com/bats-core/bats-core) suite for the
shell scripts (`sync.sh`, the status line scripts and `checkpoint.sh` under `claude/`) and the executable
command blocks documented in the skills.

The repo is mounted **read-only** and every test runs against a throwaway
`$HOME`, so the suite never touches your real `~/.claude`.

```sh
tests/run.sh          # whole suite
```

Requires Docker. The image pins `bash`, `bats`, `jq`, `git`, and `gawk`.
