#!/bin/bash
# Feed the status line's two progress readings for the session that runs this.
#
#   statusline-progress.sh estimate <pct> [<n>/<m>|-] [<HH:MM>|-]
#       The task's estimated progress, and its ETA on the local clock.
#       /progress updates are read from the transcript on their own; this is
#       for anything else that knows how far along it is.
#   statusline-progress.sh estimate clear
#
#   statusline-progress.sh run <name> -- <command> [args...]
#       Run a long command and show its real progress: the last "NN%" in its
#       output (pytest's "[ 38%]", tqdm's " 45%|███"). Output passes through
#       byte for byte as it arrives, stderr merged into stdout; the exit code
#       is the command's. The row ends as done, failed with the exit code, or
#       killed. A TERM or HUP sent to the wrapper alone is passed on to the
#       command; Ctrl-C already reaches both. It reads killed only if the
#       command then fails; one that finishes with 0 reads done, or ended at
#       its last percentage if the wrapper passed it the signal. Needs perl;
#       without it the command runs unwatched.
#   <command> | statusline-progress.sh watch <name>
#       The same for output that is already flowing (a pipe, `tail -f log`).
#       The row ends as "ended" at end of input (killed after a Ctrl-C);
#       watch cannot see an exit code. A TERM or HUP stops it at once, and
#       the row reads killed.
#   statusline-progress.sh job <name> <pct>|done|clear
#       Set a job row by hand.
#
# The session is CLAUDE_CODE_SESSION_ID, which Claude Code exports to every
# command it runs. Without it nothing can be shown, so this says so and exits
# 2 — except `run`, which still runs the command. If the cache can't be
# written, this says so too; estimate and job exit 1, run still runs.

LIB="$(dirname "${BASH_SOURCE[0]}")/statusline-lib.sh"
if ! . "$LIB" 2>/dev/null; then
  echo "statusline-progress: $LIB is missing; re-run sync.sh" >&2
  exit 2
fi

SID="${CLAUDE_CODE_SESSION_ID:-}"

# Read the clock per write: a `run` can outlast the lib's "now" by hours.
# STATUSLINE_NOW pins it, as it does for the status line, for tests.
stamp_now() { printf '%s' "${STATUSLINE_NOW:-$(date +%s)}"; }

usage() { sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

no_session() {
  echo "statusline-progress: CLAUDE_CODE_SESSION_ID is unset or unusable; nothing shown" >&2
}

cannot_write() {
  echo "statusline-progress: cannot write $PROGRESS_DIR; nothing shown" \
    "(a sandbox must allow writes there)" >&2
}

# Write a progress file, or say why not. A new file prunes month-old ones on
# the way, as the status line does when it caches an estimate, so a session
# that only runs jobs is pruned too.
put() { # path content
  local fresh=""
  [ -e "$1" ] || fresh=1
  write_atomic "$1" "$2" || { cannot_write; return 1; }
  [ -z "$fresh" ] || progress_prune
  return 0
}

# A percentage as an integer 0..100, or nothing. "38.5" reads as 38.
as_pct() { progress_pct "${1%%.*}"; }

# The process's PID namespace, so the status line checks the PID only where
# it means the same process: on Linux a sandbox may have its own.
pid_ns() { readlink /proc/self/ns/pid 2>/dev/null || echo -; }

# A job's file, named from the job but safe as a file name: letters, digits,
# "_" and "-" only, so it never starts with a dot (".." would be the parent,
# ".x" hidden) and never looks like a temp file. Names that map to the same
# slug ("a b" and "a_b") share a row.
job_file() { # name -> path, or nothing
  local dir slug
  dir=$(progress_jobs_dir "$SID")
  [ -n "$dir" ] || return 0
  slug=$(printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9_-' '_' | cut -c1-60)
  [ -n "$slug" ] && printf '%s/%s' "$dir" "$slug"
}

# The name as shown: no control characters, at most 80 characters.
job_name() { # name -> name
  local n
  n=$(printf '%s' "$1" | progress_clean 80)
  [ -n "$n" ] || n=$(basename "$(job_file "$1")")
  printf '%s' "$n"
}

# A job row: written<TAB>pct<TAB>state<TAB>name<TAB>pid<TAB>pid-namespace.
# state is run, done, end, fail:<code> or fail:sig; pid is the process that
# writes a running row, "-" for a row set by hand. Rows without the last two
# fields (an older writer) still render, unchecked.
job_set() { # name pct state [pid]
  local f
  f=$(job_file "$1")
  [ -n "$f" ] || return 0
  put "$f" "$(stamp_now)	$2	$3	$(job_name "$1")	${4:--}	$(pid_ns)"
}

# The streaming reader. Input passes to output unchanged, as it arrives, and
# a copy is scanned for the last "NN%". \r and \n both end a reading, so a
# tqdm bar counts as it redraws, and a number split across two reads is
# joined before it is read. The row is written at most once a second and
# once more at the end, by this process itself, with its own PID; the name
# and the file come in through the environment, never through a command line.
#
# With a command in @ARGV (run), this process is the wrapper itself (the
# shell execs it) and the command's parent: it reads the command's output
# from a pipe, waits for it, writes the final row and exits with its code.
# A TERM or HUP sent to the wrapper alone is passed on to the command, so it
# stops. INT is not passed on: Ctrl-C reaches the whole foreground group, the
# command included, and a second INT would cut short a test runner that
# prints a summary on the first. Either way this keeps reading to the
# command's end, so its last output is kept. The row reads killed only if
# the command then exits non-zero: one that ignored the signal and finished
# with 0 did its work, and reads done; one this process passed a TERM or HUP
# to and that then exits 0 stopped cleanly, and reads ended at its last
# percentage, not a full bar. (Counting only a command that died of the signal would
# miss the test runner, which catches INT and exits with its own code.)
#
# Without a command (watch), the shell execs it too, and it reads stdin. INT
# is left to the producer, which Ctrl-C reaches as well: its end of input
# ends the row as killed. A TERM or HUP stops the reading at once, since a
# producer such as `tail -f` never ends, and the row reads killed.
#
# A signal this process got ignored (nohup, a script's background job) stays
# ignored, here and in the command, and never makes a row read killed.
STREAM_PL='
use strict; use warnings; use Fcntl; use POSIX ();
my ($file, $name, $ns, $now) = @ENV{qw(SP_FILE SP_NAME SP_NS STATUSLINE_NOW)};
my @cmd = @ARGV;
my %orig = map { $_ => $SIG{$_} } qw(INT TERM HUP PIPE);
my %num = (INT => 2, HUP => 1, TERM => 15);
my ($child, $reaped, $got, $fwd) = (0, 0, "", 0);
sub ignored { (($orig{$_[0]} // "") eq "IGNORE") }
$SIG{INT} = sub { $got ||= "INT" } unless ignored("INT");
for my $sig (qw(TERM HUP)) {
  next if ignored($sig);
  $SIG{$sig} = sub {
    $got ||= $_[0];
    $fwd = kill $_[0], $child if $child && !$reaped;
  };
}
$SIG{PIPE} = "IGNORE";  # a closed stdout ends the copy, not this process
# watch stops reading on a TERM or HUP; run reads on until the command ends.
sub stop { !@cmd && $got && $got ne "INT" }

my ($last, $shown, $lastt, $warned, $carry) = (-1, -1, 0, 0, "");
# The cache dir may hold planted files: the temp file is created O_EXCL (a
# link at its name is removed, never written through), and a dir or row that
# is a link, or a row that is not a regular file, is never replaced.
sub put { # state pct
  my ($state, $pct) = @_;
  my $t = (defined $now && $now =~ /^[0-9]+$/) ? $now : time;
  my $pid = $state eq "run" ? $$ : "-";
  (my $dir = $file) =~ s{/[^/]*\z}{};
  my $tmp = "$file.tmp.$$";
  my $ok = 0;
  if (!-l $dir && !-l $file && (!-e $file || -f $file)) {
    unlink $tmp;
    if (sysopen(my $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL, 0666)) {
      $ok = print $fh "$t\t$pct\t$state\t$name\t$pid\t$ns\n";
      $ok = close($fh) && $ok;
      $ok = $ok && rename $tmp, $file;
    }
    unlink $tmp unless $ok;
  }
  print STDERR "statusline-progress: cannot write $file; progress not shown\n"
    if !$ok && !$warned++;
  ($shown, $lastt) = ($last, time);
}

my $in = \*STDIN;
if (@cmd) {
  my ($r, $w);
  # Hold TERM and HUP from before the fork until each side is ready for them:
  # the command until its own signal settings are back, this process until
  # it knows the command to pass them on to. A signal sent in between is
  # delivered on unblocking, not lost to the handler on the other side.
  my $hold = POSIX::SigSet->new(POSIX::SIGTERM(), POSIX::SIGHUP());
  # The caller mask is kept in $mask and put back, not unblocked outright:
  # a TERM the caller had blocked stays blocked for the command.
  my $mask = POSIX::SigSet->new;
  POSIX::sigprocmask(POSIX::SIG_BLOCK(), $hold, $mask);
  # Tests widen the gap between blocking and forking, to show nothing is lost.
  select(undef, undef, undef, $ENV{SP_TEST_PREFORK_DELAY})
    if ($ENV{SP_TEST_PREFORK_DELAY} // "") =~ /^[0-9.]+$/;
  $child = pipe($r, $w) ? fork : undef;
  if (!$child) {
    # The command, with the signals as this process got them. If the pipe
    # or the fork failed, it runs unwatched in this process instead.
    if (defined $child) {
      close $r;
      open(STDOUT, ">&", $w) && open(STDERR, ">&", $w) or exit 126;
      close $w;
    } else {
      print STDERR "statusline-progress: cannot start the reader ($!); running without progress\n";
    }
    $SIG{$_} = ignored($_) ? "IGNORE" : "DEFAULT" for keys %orig;
    POSIX::sigprocmask(POSIX::SIG_SETMASK(), $mask);  # held ones land here now
    { no warnings "exec"; exec { $cmd[0] } @cmd; }
    print STDERR "statusline-progress: $cmd[0]: $!\n";
    exit($!{ENOENT} ? 127 : 126);
  }
  POSIX::sigprocmask(POSIX::SIG_SETMASK(), $mask);  # a held one is passed on
  close $w;
  $in = $r;
  # A TERM or HUP that came before the block, with no command yet to pass it
  # to, is passed on now.
  $fwd = kill $got, $child if $got && $got ne "INT" && !$fwd;
}

binmode $in; binmode STDOUT;
my $rin = ""; vec($rin, fileno($in), 1) = 1;
my $out = 1;
while (!stop()) {
  if ($last != $shown) {
    if (time != $lastt) { put("run", $last); next }
    my $n = select(my $rr = $rin, undef, undef, 1);
    next if $n <= 0;
  }
  my $got_n = sysread($in, my $buf, 65536);
  if (!defined $got_n) { next if $!{EINTR}; last }
  last if $got_n == 0;
  for (my $off = 0; $out && $off < $got_n; ) {
    my $w = syswrite(STDOUT, $buf, $got_n - $off, $off);
    if (!defined $w) { next if $!{EINTR}; $out = 0; last }
    $off += $w;
  }
  last unless $out;  # stdout is gone: stop reading, as a closed pipe would
  my $s = $carry . $buf;
  while ($s =~ /([0-9]+)(?:\.[0-9]+)?%/g) { $last = $1 + 0 if $1 <= 100 }
  # Keep what follows the last line end, for a number split across reads.
  ($carry) = $s =~ /([^\r\n]*)\z/;
  if (length $carry > 64) { $carry = substr($carry, -64); $carry =~ s/^[0-9.]+// }
}
my $pct = $last < 0 ? 0 : $last;
if (!@cmd) {
  if ($got) { put("fail:sig", $pct); exit 128 + $num{$got} }
  put("end", $pct); exit 0;
}
close $in;

my $st;
while (1) {
  my $p = waitpid($child, 0);
  if ($p == $child) { $st = $?; last }
  next if $p == -1 && $!{EINTR};
  $st = 255 << 8; last;
}
$reaped = 1;
my $rc = ($st & 127) ? 128 + ($st & 127) : $st >> 8;
if ($got && $rc) { put("fail:sig", $pct); exit 128 + $num{$got} }
elsif ($rc == 0 && $fwd) { put("end", $pct) }  # stopped by us, cleanly
elsif ($rc == 0) { put("done", 100) }
else             { put("fail:$rc", $pct) }
exit $rc;
'

stream() { # name [command args...]: execs the reader, never returns
  export SP_FILE SP_NAME SP_NS
  SP_FILE="$(job_file "$1")"; SP_NAME="$(job_name "$1")"; SP_NS="$(pid_ns)"
  shift
  exec perl -e "$STREAM_PL" -- "$@"
}

no_perl() {
  echo "statusline-progress: perl not found; running without progress" >&2
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  estimate)
    f=$(progress_estimate_file "$SID")
    [ -n "$f" ] || { no_session; exit 2; }
    if [ "${1:-}" = clear ]; then
      put "$f" "$(stamp_now)	-	-	-" || exit 1
      exit 0
    fi
    pct=$(as_pct "${1:-}"); [ -n "$pct" ] || usage
    nm="${2:--}"
    if [ "$nm" != - ]; then nm=$(progress_nm "$nm"); [ -n "$nm" ] || usage; fi
    eta="${3:--}"
    case "$eta" in -|[0-9]:[0-5][0-9]|[01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) ;; *) usage ;; esac
    # The ETA is stored as an epoch, resolved here once rather than on
    # every refresh of the status line.
    t=$(stamp_now)
    if [ "$eta" != - ]; then eta=$(clock_epoch "$eta" "$t"); eta=${eta:--}; fi
    put "$f" "$t	$pct	$nm	$eta" || exit 1
    ;;
  job)
    name="${1:-}"; [ -n "$name" ] || usage
    [ -n "$(job_file "$name")" ] || { no_session; exit 2; }
    case "${2:-}" in
      done)  job_set "$name" 100 done || exit 1 ;;
      clear) rm -f "$(job_file "$name")" ;;
      *)     pct=$(as_pct "${2:-}"); [ -n "$pct" ] || usage
             job_set "$name" "$pct" run || exit 1 ;;
    esac
    ;;
  watch)
    name="${1:-}"; [ -n "$name" ] || usage
    if [ -z "$(job_file "$name")" ]; then no_session; exec cat; fi
    command -v perl >/dev/null 2>&1 || { no_perl; exec cat; }
    job_set "$name" 0 run "$$" || exec cat
    stream "$name"
    ;;
  run)
    name="${1:-}"; [ -n "$name" ] || usage; shift
    [ "${1:-}" = -- ] && shift
    [ $# -gt 0 ] || usage
    if [ -z "$(job_file "$name")" ]; then no_session; exec "$@"; fi
    command -v perl >/dev/null 2>&1 || { no_perl; exec "$@"; }
    job_set "$name" 0 run "$$" || exec "$@"
    stream "$name" "$@"
    ;;
  *) usage ;;
esac
