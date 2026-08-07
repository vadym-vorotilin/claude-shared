# Containerized test harness for claude-shared.
# Pins the exact tools sync.sh / statusline rely on so tests are reproducible
# and never touch the host's ~/.claude.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      bats \
      jq \
      git \
      gawk \
      coreutils \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Deterministic git identity for fixture repos created inside tests.
ENV GIT_AUTHOR_NAME=test \
    GIT_AUTHOR_EMAIL=test@example.com \
    GIT_COMMITTER_NAME=test \
    GIT_COMMITTER_EMAIL=test@example.com \
    GIT_CONFIG_GLOBAL=/etc/gitconfig

RUN git config --system init.defaultBranch main

WORKDIR /repo
