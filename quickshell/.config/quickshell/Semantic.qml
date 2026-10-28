// Meaning-based search for the launcher: "edit a photo" finds GIMP, "I'm stepping away" finds Lock.
// Every searchable thing (action, app, shortcut, clipboard text) is turned into a vector once by a
// local embedding model (Ollama, EmbeddingGemma 2, text-only 270M); a query is embedded the same way
// and compared by cosine similarity. Vectors are cached on disk by the md5 of their text, so only
// new or changed things are embedded. Ollama unloads the model after a few idle minutes (~470 MB
// while loaded, ~45 MB idle). If Ollama is not running, everything here quietly does nothing.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: sem
    property string url: "http://localhost:11434/api/embed"
    property string model: "embeddinggemma-2:270m"
    property int dims: 256                // Matryoshka: the first 256 of 768 dims, re-normalised
    property string keepAlive: "5m"
    readonly property string queryPrefix: "task: search result | query: "

    property var vecs: ({})               // md5(text) -> vector
    property var keyHash: ({})            // item key -> [{ h: md5(text), adj }] (an item may have several texts)
    property bool available: true         // false after a failed request, until the next index()
    property bool busy: false
    readonly property string file: Quickshell.env("HOME") + "/.cache/quickshell/launcher-vectors.json"

    // everything is lower-cased: the model is case-sensitive, and "Fullscreen window" scored 0.73
    // against "make window fullscreen" where "fullscreen window" scored 0.83
    function docText(title, text) { return ("title: " + (title || "none") + " | text: " + (text || "")).toLowerCase() }

    function post(texts, done) {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            let embs = null
            if (xhr.status === 200) { try { embs = JSON.parse(xhr.responseText).embeddings } catch (e) {} }
            if (!embs) sem.available = false
            done(embs ? embs.map(sem.cut) : null)
        }
        xhr.open("POST", url)
        xhr.send(JSON.stringify({ model: model, input: texts, keep_alive: keepAlive }))
    }
    function cut(v) {
        const out = v.slice(0, dims)
        let s = 0
        for (const x of out) s += x * x
        s = Math.sqrt(s) || 1
        return out.map(x => Math.round(x / s * 1e4) / 1e4)
    }

    // docs: [{ key, text, adj }]; a key may appear several times (an action and each of its example
    // phrases), its score is the best of them, each plus its `adj`. Embeds what is not cached yet,
    // in batches, then saves the cache. Also loads the model, so the first query does not wait for it.
    function index(docs) {
        available = true
        const kh = {}, todo = [], seen = {}
        for (const d of docs) {
            const h = Qt.md5(model + dims + d.text)
            if (!kh[d.key]) kh[d.key] = []
            kh[d.key].push({ h: h, adj: d.adj || 0 })
            if (!vecs[h] && !seen[h]) { seen[h] = true; todo.push({ h: h, text: d.text }) }
        }
        keyHash = kh
        if (busy) return
        if (!todo.length) { post([queryPrefix + "warm up"], () => {}); return }
        busy = true
        const step = i => {
            if (i >= todo.length || !available) { busy = false; save(); return }
            const batch = todo.slice(i, i + 32)
            post(batch.map(t => t.text), embs => {
                if (embs) batch.forEach((t, n) => sem.vecs[t.h] = embs[n])
                step(i + 32)
            })
        }
        step(0)
    }

    // calls back with [{ key, cos }], best first, for every indexed key
    function search(query, done) {
        if (!available) return
        post([queryPrefix + query.toLowerCase()], embs => { if (embs) done(sem.scoreVec(embs[0])) })
    }
    // [{ key, cos }] for an already embedded (and cut) query vector, best first
    function scoreVec(q) {
        const out = []
        for (const key in keyHash) {
            let best = -1
            for (const e of keyHash[key]) {
                const v = vecs[e.h]
                if (!v) continue
                let c = e.adj
                for (let i = 0; i < q.length; i++) c += q[i] * v[i]
                if (c > best) best = c
            }
            if (best > -1) out.push({ key: key, cos: best })
        }
        return out.sort((a, b) => b.cos - a.cos)
    }

    function save() {
        // drop vectors no current item uses, so the cache does not grow forever
        const used = {}
        for (const k in keyHash) keyHash[k].forEach(e => used[e.h] = true)
        const keep = {}
        for (const h in vecs) if (used[h]) keep[h] = vecs[h]
        vecs = keep
        cache.setText(JSON.stringify({ vecs: keep }))
    }

    Process {
        running: true
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.cache/quickshell"]
    }
    FileView {
        id: cache
        path: sem.file
        atomicWrites: true
        printErrors: false
        onLoaded: { try { sem.vecs = JSON.parse(text()).vecs || {} } catch (e) {} }
    }
}
