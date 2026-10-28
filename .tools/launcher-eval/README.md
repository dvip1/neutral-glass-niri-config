# Launcher evaluation (headless)

Scores the Quickshell launcher's ranking without opening it: each query goes through the live
launcher code over IPC (`qs ipc call launcher rank "<query>" "<vector>"`), with the query embedded by
Ollama (`embeddinggemma-2:270m`) the same way the launcher does it.

    python3 evaluate.py                    # all tests_*.json: top-1 / top-3 / MRR per category,
                                           # with and without the semantic part
    python3 evaluate.py heldout.json       # the held-out set (never tune against it)
    ./sweep.sh "0.76 0.82 0.06 -0.08" ...  # cutoffs: phrase min, one-word min, window, phrase penalty

Failures go to `failures.json` (top results with their scores and cosines). Query vectors are cached
in `query_vectors.json` (git-ignored). Tests: `{"q", "expect": [keys] | ["none"|"calc"|"rule"], "cat"}`;
keys as in `qs ipc call launcher catalog`.

The test sets were written by Claude agents (Sonnet: tests_*.json; Haiku: heldout.json) from the
catalog of this machine's apps, actions and niri binds; the example phrases in
`quickshell/.config/quickshell/launcher-phrases.json` were written by separate agents that did not
see the tests. Results 2026-10-29: tests 83.9 % top-1 / 91.3 % top-3 (lexical only: ~49 %);
held-out 79.7 % top-1 before the last fixes (84.0 % after, but those fixes were informed by it).
