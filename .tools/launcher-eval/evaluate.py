#!/usr/bin/env python3
"""Headless launcher evaluation: runs test queries through the live Quickshell launcher
(`qs ipc call launcher rank`) with and without the semantic part, and reports per category.

usage: evaluate.py [tests*.json ...] [--out failures.json] [--no-lexical-baseline]
A test: {"q": "...", "expect": ["app:...", "act:...", "key:..."] | ["none"] | ["calc"] | ["rule"], "cat": "..."}
"""
import collections, concurrent.futures as cf, glob, json, os, subprocess, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
EMBED = "http://localhost:11434/api/embed"
MODEL = "embeddinggemma-2:270m"
PREFIX = "task: search result | query: "


CACHE = os.path.join(HERE, "query_vectors.json")


def embed(qs):
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    todo = sorted({q for q in qs if q not in cache})
    for i in range(0, len(todo), 64):
        body = json.dumps({"model": MODEL, "input": [PREFIX + q.lower() for q in todo[i:i + 64]], "keep_alive": "10m"}).encode()
        with urllib.request.urlopen(urllib.request.Request(EMBED, body), timeout=600) as r:
            for q, v in zip(todo[i:i + 64], json.load(r)["embeddings"]):
                cache[q] = [round(x, 5) for x in v]
    if todo:
        json.dump(cache, open(CACHE, "w"))
    return [cache[q] for q in qs]


def rank(q, vec):
    arg = ";".join(f"{x:.5f}" for x in vec) if vec else ""
    for attempt in range(20):   # Quickshell answers "Not ready" while it reloads
        r = subprocess.run(["qs", "ipc", "call", "launcher", "rank", q, arg], capture_output=True, text=True, timeout=30)
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            time.sleep(0.5)
    return [{"key": "ERROR", "kind": "error", "title": r.stdout[:80] + r.stderr[:80], "score": 0}]


def judge(t, res):
    """-> (top1 ok, top3 ok, reciprocal rank)"""
    exp = t["expect"]
    local = [r for r in res if r["kind"] != "web"]
    if exp == ["none"]:
        ok = not local
        return ok, ok, 1.0 if ok else 0.0
    if exp in (["calc"], ["rule"]):
        ok = bool(res) and res[0]["kind"] == exp[0]
        return ok, ok, 1.0 if ok else 0.0
    hit = [any(k in exp for k in [r["key"]] + r.get("aliases", [])) for r in res]   # merged action+shortcut rows
    rr = next((1 / (i + 1) for i, h in enumerate(hit) if h), 0.0)
    return bool(hit) and hit[0], any(hit[:3]), rr


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else os.path.join(HERE, "failures.json")
    if "--out" in sys.argv:
        args.remove(out)
    files = args or sorted(glob.glob(os.path.join(HERE, "tests_*.json")))
    tests = []
    for f in files:
        for t in json.load(open(f)):
            if t.get("q") and t.get("expect"):
                t["file"] = os.path.basename(f)
                tests.append(t)
    t0 = time.time()
    vecs = embed([t["q"] for t in tests])
    t1 = time.time()
    modes = {"semantic": vecs}
    if "--no-lexical-baseline" not in sys.argv:
        modes["lexical"] = [None] * len(tests)
    results = {}
    with cf.ThreadPoolExecutor(8) as ex:
        for m, vs in modes.items():
            results[m] = list(ex.map(lambda tv: rank(tv[0]["q"], tv[1]), zip(tests, vs)))
    t2 = time.time()
    print(f"{len(tests)} tests from {len(files)} files; embed {t1 - t0:.1f}s, rank {t2 - t1:.1f}s ({len(modes)} modes)\n")

    for m in modes:
        stats = collections.defaultdict(lambda: [0, 0, 0, 0.0])
        for t, res in zip(tests, results[m]):
            a, b, rr = judge(t, res)
            for c in (t["cat"], "ALL"):
                s = stats[c]; s[0] += 1; s[1] += a; s[2] += b; s[3] += rr
        print(f"== {m}")
        print(f"  {'category':16} {'n':>4} {'top1':>6} {'top3':>6} {'mrr':>5}")
        for c in sorted(stats, key=lambda c: (c == "ALL", c)):
            n, a, b, rr = stats[c]
            print(f"  {c:16} {n:4} {a / n:6.1%} {b / n:6.1%} {rr / n:5.2f}")
        print()

    fails = []
    for t, res, lex in zip(tests, results["semantic"], results.get("lexical", [None] * len(tests))):
        a, _, _ = judge(t, res)
        if not a:
            fails.append({"q": t["q"], "cat": t["cat"], "expect": t["expect"],
                          "got": [f'{r["title"]} [{r["key"]}{"+" + ",".join(r["aliases"]) if r.get("aliases") else ""}] {r["score"]}' + (f' cos {r["cos"]:.3f}' if r.get("cos") else "") for r in res[:4]],
                          "lexical_ok": judge(t, lex)[0] if lex else None})
    json.dump(fails, open(out, "w"), indent=1, ensure_ascii=False)
    regress = sum(1 for f in fails if f["lexical_ok"])
    print(f"{len(fails)} top-1 failures written to {out} ({regress} of them were right without semantic)")


if __name__ == "__main__":
    main()
