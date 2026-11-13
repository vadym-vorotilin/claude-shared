# Clicker tier test: how to run it

This folder holds the fixture and the harness for picking the tier of the "UI clicker" row of the `/agency` skill's `matrix.md`. The fixture is Tallyleaf, a fictional invoicing tool of three static pages with 20 seeded defects. `answer-key.md` lists them; clickers never see it. Nothing here records results.

## Files

- `fixture/`: `index.html`, `settings.html`, `reports.html`. Inline CSS and JS only; no external resources.
- `answer-key.md`: `id | category | page | element | description`, ids K01 to K20, and the hit kinds `look.sh checks` should return per page. `tests/swarm-eval.bats` checks the fixture against it.
- `score-brief.md`: the brief for a scorer agent.
- `judge-brief.md`: the brief for a blind judge agent.

## Serve the fixture

The reports page asks for a file that does not exist (one of the seeded defects), so serve over http, on 127.0.0.1 only, from this folder's `fixture/`:

    python3 -m http.server 0 --bind 127.0.0.1 --directory fixture

Read the port it prints, and stop the server by the pid you started. The start URL for the charters is `http://127.0.0.1:<port>/index.html`, and the one host a clicker may use is `127.0.0.1`.

## Run it

1. **Charters.** Write the charters once, in a private location outside the repo, and do not change them between runs: the same files, the same start URL, angles, widths and schemes for every run of every arm. Several charters, each covering a different angle (for example one per page and one cross-page), so a run's notes can reach most of the 20 defects.
2. **Two arms, same charters.** An arm is one clicker setting: a "cheap" arm and a "mid" arm, as the matrix names its tiers. Run `/swarm-of-clickers` on the fixture for each arm, several runs per arm, with the review step skipped: the scorer reads each clicker's raw `notes.json`, not the caller's merged findings. Keep the runs apart: one run directory per arm per run, `<run>/clickers/<name>/notes.json` with the shots beside them. Name every run directory and every clicker session with an opaque id (`r1`, `r2`, ... `r6`) that carries no arm, tier or model word, so no path a judge sees (the shot paths in `notes.json` are absolute paths into the run directory) gives the arm away. Keep the id-to-arm mapping in a private notes file outside the runs and outside anything a judge is pointed at, until all verdicts are in.
3. **Score.** For each run, dispatch a fresh agent on the "Review that gates a merge or a ship" row of the matrix (the scores gate the matrix row) with `score-brief.md`, the answer key path, the run directory and an output path for the CSV. It returns one tally line and writes `id,matched_key,category`. Per arm and category, recall is the distinct key ids matched in that category over the key's count for it, averaged over the arm's runs. Also record false findings per run, and the tokens each run spent per distinct real defect.
4. **Judge, blind and pairwise.** For each pairing of one run per arm, shuffle which arm is X and which is Y, and keep that mapping private too (the same place as the run-id mapping, never in a run directory). Dispatch a fresh agent on the "Adversarial check of a recommendation" row of the matrix with `judge-brief.md`, the key and the two run directories under the labels X and Y. It returns `verdict: X | Y | tie` and up to 5 reasons. Map the verdicts back to the arms. Take three pairings.
5. **Decide.** Cheap wins if its recall is within 10 points of mid in every category and the judges do not prefer mid 2 of 3; otherwise mid. Set the "UI clicker" row of the matrix to the winner and drop its *U* mark.

Numbers, verdicts and charters stay in a private notes file outside the repo. Only the matrix row is committed.
