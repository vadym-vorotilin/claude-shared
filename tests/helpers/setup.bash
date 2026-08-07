# Common setup/teardown + assertion helpers, loaded by every .bats file.
#
# Isolation: each test gets a throwaway $HOME under a fresh temp dir, so
# sync.sh deploys into a sandbox ~/.claude and never touches the real one.

# Repo under test. Mounted read-only at /repo inside the container.
: "${REPO_ROOT:=/repo}"

common_setup() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME"
  export REPO="$REPO_ROOT"
}

common_teardown() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
}

# ---- assertions ----------------------------------------------------------

fail() { echo "ASSERT FAILED: $*" >&2; return 1; }

assert_equal() { # actual expected
  [ "$1" = "$2" ] || fail "expected [$2] but got [$1]"
}

assert_contains() { # haystack needle
  case "$1" in
    *"$2"*) : ;;
    *) fail "expected output to contain [$2]; got: $1" ;;
  esac
}

refute_contains() { # haystack needle
  case "$1" in
    *"$2"*) fail "expected output NOT to contain [$2]; got: $1" ;;
    *) : ;;
  esac
}

assert_file_exists() { [ -e "$1" ] || fail "missing file: $1"; }
assert_symlink()     { [ -L "$1" ] || fail "not a symlink: $1"; }
assert_executable()  { [ -x "$1" ] || fail "not executable: $1"; }

# Count occurrences of a fixed string across a file.
count_occurrences() { # file needle
  grep -cF -- "$2" "$1" 2>/dev/null || true
}

# ---- fixture builders ----------------------------------------------------

# Initialize a git repo at $1 with one commit on branch main.
make_git_repo() { # dir
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  echo "seed" > "$d/seed.txt"
  git -C "$d" add seed.txt
  git -C "$d" commit -q -m "seed"
}

# Initialize $1 as a clone of a fresh bare upstream, returning a repo whose
# branch tracks origin/main. Used for ahead/behind statusline tests.
make_git_repo_with_upstream() { # workdir
  local work="$1"
  local bare="$TEST_TMP/upstream.git"
  git init -q --bare -b main "$bare"
  git clone -q "$bare" "$work"
  echo "seed" > "$work/seed.txt"
  git -C "$work" add seed.txt
  git -C "$work" commit -q -m "seed"
  git -C "$work" push -q -u origin main
}
