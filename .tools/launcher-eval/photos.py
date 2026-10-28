#!/usr/bin/env python3
"""Photo search quality, using wallpapers whose file names describe them ("a_sports_car_with_neon_lights.png")
as labelled data: the name (never indexed: photos are embedded from pixels only) is the query, and the
picture should come back near the top. Unrelated queries (tests_mixed.json "none-web") give the noise
level for the cut-off in file-index (MIN["photo"]).

usage: photos.py [max_queries]
"""
import json, os, random, re, sqlite3, sys, urllib.request
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.expanduser("~/.cache/file-index/index.db")


def embed(texts):
    out = []
    for i in range(0, len(texts), 64):
        body = json.dumps({"model": "embeddinggemma-2:270m", "input": ["task: search result | query: " + t.lower() for t in texts[i:i + 64]]}).encode()
        for v in json.load(urllib.request.urlopen(urllib.request.Request("http://localhost:11434/api/embed", body), timeout=600))["embeddings"]:
            v = np.asarray(v[:256], dtype=np.float32)
            out.append(v / np.linalg.norm(v))
    return np.stack(out)


rows = sqlite3.connect(DB).execute("SELECT path, vec FROM files WHERE kind = 'photo' AND vec IS NOT NULL").fetchall()
paths = [r[0] for r in rows]
M = np.frombuffer(b"".join(r[1] for r in rows), dtype=np.float16).reshape(len(rows), 256).astype(np.float32)
labelled = [(i, re.sub(r"_+", " ", os.path.splitext(os.path.basename(p))[0]).strip()) for i, p in enumerate(paths)
            if "/walls/" in p and re.match(r"(a|an|the)_", os.path.basename(p))]
labelled = [(i, re.sub(r"\s+\d+$", "", q)) for i, q in labelled]   # "a cat 2" -> "a cat"
random.seed(7)
random.shuffle(labelled)
labelled = labelled[: int(sys.argv[1]) if len(sys.argv) > 1 else 400]
print(f"{len(paths)} photos indexed, {len(labelled)} labelled queries")

Q = embed([q for _, q in labelled])
S = Q @ M.T
ranks, right = [], []
for k, (i, q) in enumerate(labelled):
    order = np.argsort(-S[k])
    ranks.append(int(np.where(order == i)[0][0]) + 1)
    right.append(float(S[k, i]))
ranks = np.array(ranks)
print(f"right photo first: {np.mean(ranks == 1):.1%}   in top 5: {np.mean(ranks <= 5):.1%}   in top 20: {np.mean(ranks <= 20):.1%}   median rank {int(np.median(ranks))}")
print(f"cosine of the right photo: p10 {np.percentile(right, 10):.3f}  median {np.median(right):.3f}  p90 {np.percentile(right, 90):.3f}")

none = [t["q"] for t in json.load(open(os.path.join(HERE, "tests_mixed.json"))) if t["cat"] == "none-web"]
N = embed(none) @ M.T
best = N.max(axis=1)
print(f"unrelated queries ({len(none)}), best photo cosine: median {np.median(best):.3f}  p90 {np.percentile(best, 90):.3f}  max {best.max():.3f}")
for cut in (0.50, 0.55, 0.58, 0.60, 0.62, 0.65):
    print(f"  cut {cut:.2f}: keeps the right photo {np.mean(np.array(right) >= cut):.0%} of the time, shows a photo for {np.mean(best >= cut):.0%} of unrelated queries")
worst = sorted(zip(ranks, [q for _, q in labelled]), reverse=True)[:5]
print("hardest:", [(int(r), q[:50]) for r, q in worst])
