// The launcher (Mod+D / Alt+Space; replaces fuzzel as the app launcher, fuzzel stays for the
// dmenu-style menus). Ideas borrowed from Spotlight (Tahoe), Raycast and Alfred:
//   - one list for apps (and their desktop actions), open windows, actions, files and clipboard,
//     ranked live while typing, with frequently/recently used things first
//   - sections like Spotlight's Cmd+1..4: Ctrl+1..6 = All, Apps, Windows, Files, Actions, Clipboard
//     (Tab / Shift+Tab cycle them)
//   - it remembers what you picked for a query (Alfred's "knowledge"), so "f" learns to mean Firefox
//   - quick keys for actions ("dm" dark mode, "lk" lock, ...)
//   - calculator and unit conversion inline ("2^10", "sqrt(2)*3", "5 km in mi", "100 f to c")
//   - prefixes: "=" calculator, "/" or "~" files, ">" shell command, "?" web search
//   - the last row searches the web for what you typed
//   - keyboard shortcuts from niri's config are searchable and runnable ("fullscreen" -> Mod+Shift+F)
//   - "brightness 40", "volume 30" set them directly
//   - search by meaning (Semantic.qml, a local embedding model through Ollama): "edit a photo" finds
//     an image editor, "I'm stepping away" finds Lock. Those matches arrive ~50 ms after the normal
//     ones and are mixed in; without Ollama the launcher works as before.
// Enter = the default action, Ctrl+Enter = the alternative where there is one (file: open its
// folder; "> command": run it without a terminal).
// The surface is fixed-size (never resized while animating, see Sheet.qml); niri blurs it via
// the "launcher" layer-rule. A click outside closes it (invisible catcher layer under it).
//   qs ipc call launcher toggle
//   qs ipc call launcher section <all|apps|windows|files|actions|clipboard>
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    property var screen
    property bool want: false
    property real open: 0

    readonly property string home: Quickshell.env("HOME")
    readonly property string bin: home + "/.local/bin/"
    readonly property string webSearch: "https://duckduckgo.com/?q="
    readonly property var sections: [
        { id: "all", label: "All" }, { id: "apps", label: "Apps" }, { id: "windows", label: "Windows" },
        { id: "files", label: "Files" }, { id: "actions", label: "Actions" }, { id: "clipboard", label: "Clipboard" }
    ]
    property int section: 0
    property string query: ""
    property var items: []            // the current results (plain JS objects, looked up by index)
    property int current: 0
    property var lastPointer: null

    // live data, refreshed each time the launcher opens
    property var windows: []
    property var clips: []
    property var recentFiles: []
    property var foundFiles: []       // plocate results for the current query
    property var binds: []            // keyboard shortcuts parsed from niri's config
    property var semHits: ({})        // semantic key -> cosine, for the current query
    property string semFor: ""
    property bool debug: false        // `qs ipc call launcher debug`: log each result's scores
    // semantic tuning (measured with the headless harness, see rankJson); `qs ipc call launcher tune` changes them live
    property real semMin: 0.76        // cosine below this is noise (tuned on ~1500 test queries)
    property real semMin1: 0.82       // the same for a one-word query: little meaning, so noise scores high
    property real semWindow: 0.06     // and only matches this close to the best one
    property real phraseAdj: -0.08    // short example phrases match noise more readily
    property string foundFor: ""

    // ---- open / close ----
    function show(sec) {
        section = sec === undefined ? 0 : sec
        query = ""
        field.text = ""
        current = 0
        lastPointer = null
        foundFiles = []; foundFor = ""
        semHits = {}; semFor = ""
        winProc.running = true
        clipProc.running = true
        recentView.reload()
        want = true
        refresh()
    }
    function hide() { want = false }
    function toggle() { want ? hide() : show(0) }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggle() }
        function debug(): void { root.debug = !root.debug; console.warn("launcher debug", root.debug) }
        // headless testing
        function rank(q: string, vec: string): string { return root.rankJson(q, "all", vec) }
        function rankIn(q: string, sec: string, vec: string): string { return root.rankJson(q, sec, vec) }
        function catalog(): string { return root.catalogJson() }
        function reindex(): void { root.indexAll() }
        function indexing(): bool { return sem.busy }
        function tune(min: real, min1: real, win: real, adj: real): void { root.semMin = min; root.semMin1 = min1; root.semWindow = win; root.phraseAdj = adj; root.indexAll() }
        function section(name: string): void {
            const i = root.sections.findIndex(s => s.id === name)
            if (root.want && root.section === i) root.hide()
            else if (root.want) root.setSection(Math.max(0, i))
            else root.show(Math.max(0, i))
        }
    }

    onWantChanged: {
        if (want) { shut.stop(); open = 0; grow.restart(); field.forceActiveFocus() }
        else { grow.stop(); shut.restart() }
    }
    NumberAnimation { id: grow; target: root; property: "open"; to: 1; duration: 150; easing.type: Easing.OutCubic }
    NumberAnimation { id: shut; target: root; property: "open"; to: 0; duration: 100; easing.type: Easing.InCubic }

    function setSection(i) {
        section = (i + sections.length) % sections.length
        current = 0
        refresh()
    }

    // ---- usage memory: frecency per item, and which item was picked for which query ----
    property var usage: ({})          // key -> { n: count, t: last use (ms) }
    property var picks: ({})          // lower-case query -> key
    readonly property string stateFile: home + "/.local/state/quickshell/launcher.json"
    function frecency(key) {
        const u = usage[key]
        if (!u) return 0
        const hours = (Date.now() - u.t) / 3600000
        return u.n / (1 + hours / 72)
    }
    function remember(item) {
        if (!item.key) return
        const u = usage[item.key] || { n: 0, t: 0 }
        usage[item.key] = { n: Math.min(u.n + 1, 500), t: Date.now() }
        const q = query.trim().toLowerCase()
        if (q && item.kind !== "calc" && item.kind !== "web") picks[q] = item.key
        // keep the file small: drop the oldest picks beyond 300
        const qs = Object.keys(picks)
        if (qs.length > 300) delete picks[qs[0]]
        stateView.setText(JSON.stringify({ usage: usage, picks: picks }))
    }
    Process {
        running: true
        command: ["mkdir", "-p", root.home + "/.local/state/quickshell"]
    }
    FileView {
        id: stateView
        path: root.stateFile
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.usage = d.usage || {}
                root.picks = d.picks || {}
            } catch (e) {}
        }
    }

    // ---- matching ----
    // returns { score, hits: [char indices] } or null. Higher is better.
    function match(q, s) {
        if (!s) return null
        const l = s.toLowerCase()
        if (l === q) return { score: 1000, hits: range(0, q.length) }
        if (l.startsWith(q)) return { score: 900 - (l.length - q.length) + (/[\s\-_.\/]/.test(l[q.length]) ? 40 : 0), hits: range(0, q.length) }
        // at the start of a word
        const re = /[\s\-_.\/]/
        let i = l.indexOf(q)
        while (i > 0 && !re.test(l[i - 1])) i = l.indexOf(q, i + 1)
        if (i > 0) return { score: 800 - i, hits: range(i, i + q.length) }
        // initials: "vsc" -> Visual Studio Code
        const starts = []
        for (let k = 0; k < l.length; k++) if (k === 0 || re.test(l[k - 1]) || (s[k] !== l[k] && s[k - 1] === l[k - 1])) starts.push(k)
        if (q.length >= 2 && q.length <= starts.length && starts.slice(0, q.length).every((k, n) => l[k] === q[n]))
            return { score: 750, hits: starts.slice(0, q.length) }
        i = l.indexOf(q)
        if (i >= 0) return { score: 600 - i, hits: range(i, i + q.length) }
        // every word of the query somewhere
        const words = q.split(/\s+/).filter(w => w)
        if (words.length > 1 && words.every(w => l.includes(w))) {
            let hits = []
            words.forEach(w => { const p = l.indexOf(w); hits = hits.concat(range(p, p + w.length)) })
            return { score: 450, hits: hits }
        }
        // subsequence, penalised by the gaps (only for one short word: "frfx" -> Firefox; on
        // phrases it matches nearly anything, the semantic search covers those)
        if (q.length < 3 || q.includes(" ")) return null
        let hits = [], p = 0, gaps = 0
        for (const c of q) {
            if (c === " ") continue
            const f = l.indexOf(c, p)
            if (f < 0) return null
            if (hits.length) gaps += f - p
            hits.push(f); p = f + 1
        }
        if (gaps > 2 * q.length + 4) return null
        return { score: 300 - gaps * 4, hits: hits }
    }
    function range(a, b) { const r = []; for (let i = a; i < b; i++) r.push(i); return r }
    // best of the title (with highlight) and other words (keywords, generic name: no highlight)
    function matchItem(q, title, extra) {
        const m = match(q, title)
        let best = m ? m : null
        for (const e of extra || []) {
            const x = match(q, e)
            if (x && x.score >= 450 && (!best || x.score * 0.7 > best.score)) best = { score: x.score * 0.7, hits: m ? m.hits : [] }
        }
        // one mistyped word ("fierfox", "termnial"): close to a word of the title or of the extras
        if (!best && q.length >= 4 && !q.includes(" ")) {
            const limit = q.length >= 7 ? 2 : 1
            let d = 9
            for (const w of [title].concat(extra || []).join(" ").toLowerCase().split(/[\s\-_.\/]+/))
                if (w.length >= 3 && Math.abs(w.length - q.length) <= limit) d = Math.min(d, typoDist(q, w, limit))
            if (d <= limit) best = { score: 420 - 80 * d, hits: [] }
        }
        return best
    }
    // edit distance counting a swap of two neighbours as one edit; gives up past `limit`
    function typoDist(a, b, limit) {
        const n = a.length, m = b.length
        let prev2 = null, prev = range(0, m + 1)
        for (let i = 1; i <= n; i++) {
            const cur = [i]
            let low = i
            for (let j = 1; j <= m; j++) {
                let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1))
                if (prev2 && i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1)
                cur.push(v)
                low = Math.min(low, v)
            }
            if (low > limit) return limit + 1
            prev2 = prev; prev = cur
        }
        return prev[m]
    }

    // ---- calculator and unit conversion ----
    readonly property var units: ({
        // length (m)
        mm: ["len", 0.001], cm: ["len", 0.01], m: ["len", 1], km: ["len", 1000], in: ["len", 0.0254], inch: ["len", 0.0254],
        ft: ["len", 0.3048], foot: ["len", 0.3048], feet: ["len", 0.3048], yd: ["len", 0.9144], mi: ["len", 1609.344], mile: ["len", 1609.344], miles: ["len", 1609.344],
        // mass (kg)
        mg: ["mass", 1e-6], g: ["mass", 0.001], kg: ["mass", 1], t: ["mass", 1000], oz: ["mass", 0.028349523125], lb: ["mass", 0.45359237], lbs: ["mass", 0.45359237],
        // volume (l)
        ml: ["vol", 0.001], l: ["vol", 1], gal: ["vol", 3.785411784], cup: ["vol", 0.2365882365], floz: ["vol", 0.0295735295625],
        // data (bytes)
        b: ["data", 1], kb: ["data", 1e3], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12],
        kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
        // time (s)
        ms: ["time", 0.001], s: ["time", 1], sec: ["time", 1], min: ["time", 60], h: ["time", 3600], hr: ["time", 3600], day: ["time", 86400], days: ["time", 86400], week: ["time", 604800], weeks: ["time", 604800],
        // speed (m/s)
        kmh: ["speed", 1 / 3.6], mph: ["speed", 0.44704], mps: ["speed", 1], kn: ["speed", 0.514444],
        // temperature: special-cased
        c: ["temp", 0], f: ["temp", 0], k: ["temp", 0]
    })
    // spelled-out names -> the short ones above
    readonly property var unitNames: ({
        millimeter: "mm", millimetre: "mm", centimeter: "cm", centimetre: "cm", meter: "m", metre: "m", kilometer: "km", kilometre: "km",
        inches: "in", yard: "yd", yards: "yd", milligram: "mg", gram: "g", grams: "g", kilogram: "kg", kilo: "kg", kilos: "kg",
        ton: "t", tonne: "t", ounce: "oz", ounces: "oz", pound: "lb", pounds: "lb", milliliter: "ml", millilitre: "ml", liter: "l",
        litre: "l", gallon: "gal", gallons: "gal", cups: "cup", byte: "b", bytes: "b", kilobyte: "kb", megabyte: "mb", gigabyte: "gb",
        terabyte: "tb", second: "s", seconds: "s", secs: "s", minute: "min", minutes: "min", mins: "min", hour: "h", hours: "h",
        hrs: "h", celsius: "c", centigrade: "c", fahrenheit: "f", kelvin: "k", kph: "kmh", knots: "kn"
    })
    function unitOf(w) {
        if (units[w]) return w
        if (unitNames[w]) return unitNames[w]
        const one = w.replace(/e?s$/, "")          // meters, kilometres, terabytes
        return unitNames[one] || (units[one] ? one : null)
    }
    function fmt(x) {
        if (!isFinite(x)) return null
        if (Math.abs(x) >= 1e15 || (Math.abs(x) < 1e-6 && x !== 0)) return x.toExponential(6).replace(/\.?0+e/, "e")
        return String(Math.round(x * 1e10) / 1e10)
    }
    function convert(text) {
        const t = text.trim().toLowerCase()
            .replace(/^(?:what(?:'s| is)|how much is|calculate|calc)\s+/, "").replace(/\s*\?$/, "")
            .replace(/^tip\s+([\d.]+)\s*%\s+(?:on|of)\s+/, "$1% of ")
        const pct = t.match(/^(-?[\d.]+)\s*(?:%|percent)\s+of\s+(-?[\d.]+)$/)
        if (pct) return fmt(parseFloat(pct[1]) / 100 * parseFloat(pct[2]))
        const raw = t.match(/^(-?[\d.]+(?:e-?\d+)?)\s*°?\s*([a-z]+)\s+(?:to|in|into|as|=)\s+°?\s*([a-z]+)$/)
        if (!raw) return null
        const m = [raw[0], raw[1], unitOf(raw[2]), unitOf(raw[3])]
        const v = parseFloat(m[1]), a = units[m[2]], b = units[m[3]]
        if (isNaN(v) || !a || !b || a[0] !== b[0]) return null
        let r
        if (a[0] === "temp") {
            const c = m[2] === "c" ? v : m[2] === "f" ? (v - 32) * 5 / 9 : v - 273.15
            r = m[3] === "c" ? c : m[3] === "f" ? c * 9 / 5 + 32 : c + 273.15
        } else r = v * a[1] / b[1]
        const s = fmt(Number(r.toPrecision(6)))
        return s === null ? null : s + " " + m[3]
    }
    readonly property var mathNames: ["sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "log2", "log10",
        "exp", "abs", "round", "floor", "ceil", "min", "max", "pow", "pi", "e"]
    function calc(text) {
        let t = text.trim().replace(/^=/, "").trim().toLowerCase()
            .replace(/^(?:what(?:'s| is)|how much is|calculate|calc)\s+/, "").replace(/\s*\?$/, "")
            .replace(/(\d)\s*(?:x|times)\s*(?=[\d(])/g, "$1*").replace(/\s+plus\s+/g, "+").replace(/\s+minus\s+/g, "-")
            .replace(/\s+divided by\s+/g, "/").replace(/\s+over\s+/g, "/")
        if (!t) return null
        const conv = convert(t)
        if (conv) return conv
        // only digits, operators and known function names; must contain an operator or a function
        const names = t.match(/[a-z]+/gi) || []
        if (!names.every(n => mathNames.includes(n.toLowerCase()))) return null
        if (!/[\d)]\s*[-+*/%^]|[a-z]\s*\(|^-|pi|\be\b/i.test(t) && !text.startsWith("=")) return null
        if (!/^[\d\s.,+\-*/%^()a-z]+$/i.test(t)) return null
        t = t.replace(/(\d),(\d{3})/g, "$1$2").replace(/\^/g, "**").replace(/(\d)\s*%(?!\s*[\d(])/g, "($1/100)")
             .replace(/\bln\b/gi, "log").replace(/\blog\b(?!\d)/gi, "log10x")
             .replace(/[a-z][a-z0-9]*/gi, n => n === "log10x" ? "Math.log10" : n.toLowerCase() === "pi" ? "Math.PI"
                      : n.toLowerCase() === "e" ? "Math.E" : n.toLowerCase() === "log" ? "Math.log" : "Math." + n.toLowerCase())
        try {
            const r = (new Function("return (" + t + ")"))()
            return typeof r === "number" ? fmt(r) : null
        } catch (e) { return null }
    }

    // ---- sources ----
    function apps() {
        return DesktopEntries.applications.values.filter(e => !e.noDisplay && !e.command.join(" ").includes("/.local/bin/"))
    }
    function appItem(e) {
        return { key: "app:" + e.id, skey: "app:" + e.id, kind: "app", title: e.name, sub: e.comment || e.genericName || "",
                 image: e.icon, glyph: "󰣆", hint: "Open", tag: "Application",
                 doc: sem.docText(e.name, [e.comment, e.genericName, (e.keywords || []).join(", "), (e.categories || []).join(", ")].filter(x => x).join(". ")),
                 extra: [e.genericName, (e.keywords || []).join(" "), e.id, e.command.length ? e.command[0].split("/").pop() : ""],
                 run: () => e.execute() }
    }
    function sh(script) { return ["sh", "-c", script] }
    function act(id, title, glyph, keys, cmd, sub) {
        // a niri bind that runs the same thing is shown on this row (its key in the tag) instead of twice
        const combos = typeof cmd === "function" ? [] : (bindSigs[cmdSig(cmd)] || [])
        for (const sg of actionSigs[id] || []) combos.push(...(bindSigs[sg] || []))
        return { key: "act:" + id, skey: "act:" + id, kind: "action", title: title, sub: sub || "", glyph: glyph, keys: keys,
                 hint: "Run", tag: combos.length ? combos[0] : "Action", aliases: combos.map(c => "key:" + c),
                 extra: keys, doc: sem.docText(title, about[id] || title),
                 run: typeof cmd === "function" ? cmd : () => Quickshell.execDetached(cmd) }
    }
    // what a command does, so an action and a bind running the same thing compare equal
    function cmdSig(cmd) {
        let c = cmd.slice()
        if (c[0] === "niri" && c[2] === "action") {
            if (c[3] !== "spawn" && c[3] !== "spawn-sh") return "niri " + c.slice(3).filter(x => x !== "--").join(" ")
            c = c.slice(4).filter(x => x !== "--")
            if (c.length === 1) c = c[0].split(/\s+/)
        }
        return c.map(x => x.replace(/^.*\//, "")).join(" ")
    }
    // actions run as functions, or differently from their bind
    readonly property var actionSigs: ({
        "lock": ["lockscreen"], "dnd": ["qs ipc call notifications dnd"], "clear-notifs": ["qs ipc call notifications clear"]
    })
    readonly property var bindSigs: {
        const m = {}
        for (const b of binds) (m[cmdSig(b.cmd)] = m[cmdSig(b.cmd)] || []).push(b.combo)
        return m
    }
    function actions() {
        const b = bin
        const list = [
            act("toggle-mode", "Toggle Dark / Light Mode", "󰔎", ["dm", "lm", "dark", "light"], [b + "theme", "toggle"]),
            act("theme-next", "Next Theme", "󰏘", ["nt", "theme"], [b + "theme", "next"]),
            act("wifi", "Wi-Fi Networks", "󰖩", ["wf", "wifi", "network"], [b + "wifi-menu"]),
            act("wifi-toggle", "Turn Wi-Fi On / Off", "󰖪", ["wt", "airplane"],
                sh('[ "$(nmcli radio wifi)" = enabled ] && nmcli radio wifi off || nmcli radio wifi on')),
            act("bt", "Bluetooth Devices", "󰂯", ["bt", "bluetooth", "headphones"], [b + "bt-menu"]),
            act("bt-toggle", "Turn Bluetooth On / Off", "󰂲", ["btt"],
                sh('bluetoothctl show | grep -q "Powered: yes" && bluetoothctl power off || bluetoothctl power on')),
            act("quick", "Quick Settings", "󰒓", ["qs", "settings"], ["qs", "ipc", "call", "quicksettings", "toggle"]),
            act("notifs", "Notifications", "󰂚", ["nf", "calendar"], ["qs", "ipc", "call", "notifications", "toggle"]),
            act("dnd", Notifs.dnd ? "Turn Off Do Not Disturb" : "Do Not Disturb", Notifs.dnd ? "󰂚" : "󰂛", ["dnd", "silence", "mute notifications"],
                () => { Notifs.dnd = !Notifs.dnd }),
            act("clear-notifs", "Clear Notifications", "󰎟", ["cn"], () => Notifs.clear()),
            act("shot-region", "Screenshot Region", "󰹑", ["ss", "screenshot"], ["niri", "msg", "action", "screenshot"]),
            act("shot-screen", "Screenshot Screen", "󰍹", ["sss"], ["niri", "msg", "action", "screenshot-screen"]),
            act("shot-window", "Screenshot Window", "󱂬", ["ssw"], ["niri", "msg", "action", "screenshot-window"]),
            act("pick-color", "Pick Colour", "󰈊", ["pc", "color", "colour", "eyedropper"],
                sh('c=$(niri msg pick-color | awk "/Hex/{print \\$2}") && [ -n "$c" ] && printf %s "$c" | wl-copy && notify-send -a Launcher "Copied $c"'),
                "Copies the hex value"),
            act("overview", "Overview", "󰕰", ["ov", "expose"], ["niri", "msg", "action", "toggle-overview"]),
            act("mute", "Mute / Unmute Sound", "󰝟", ["mute", "unmute"], ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]),
            act("volume", "Volume and Sound Output", "󰕾", ["vol", "volume", "sound"], ["qs", "ipc", "call", "quicksettings", "toggle"],
                "Quick settings; or type e.g. volume 40"),
            act("brightness", "Screen Brightness", "󰃟", ["br", "brightness"], ["qs", "ipc", "call", "quicksettings", "toggle"],
                "Quick settings; or type e.g. brightness 40"),
            act("bar", "Show / Hide Bar", "󰍜", ["bar"], ["qs", "ipc", "call", "bar", "toggle"]),
            act("shortcuts", "Keyboard Shortcuts", "󰌌", ["ks", "keys", "help"], [b + "shortcuts"]),
            act("power-settings", "Power Settings", "󰂄", ["ps", "battery"], [b + "power-settings"]),
            act("lock", "Lock Screen", "󰌾", ["lk", "lock"], [b + "power", "lock"]),
            act("suspend", "Suspend", "󰤄", ["sl", "sleep"], [b + "power", "suspend"]),
            act("logout", "Log Out", "󰍃", ["lo"], [b + "power", "logout"], "Asks first"),
            act("reboot", "Reboot", "󰜉", ["rb", "restart"], [b + "power", "reboot"], "Asks first"),
            act("shutdown", "Shut Down", "󰐥", ["sd", "poweroff"], [b + "power", "shutdown"], "Asks first")
        ]
        for (const t of ["glass", "rose-pine", "gruvbox", "everforest", "mono"])
            list.push(act("theme-" + t, "Theme: " + t.split("-").map(w => w[0].toUpperCase() + w.slice(1)).join(" "),
                          t === Theme.name ? "󰄬" : "󰏘", ["theme " + t], [b + "theme", "set", t], t === Theme.name ? "Current" : ""))
        return list
    }
    // what each action is for in plain words, and the ways people ask for each app: what the
    // semantic search matches against (titles alone are too short to carry the meaning).
    // Kept in launcher-phrases.json (written with help from Claude agents, edit freely).
    property var about: ({})
    property var appPhrases: ({})
    property var keyPhrases: ({})     // shortcuts, by what they run (cmdSig), so every bind of an action shares them
    FileView {
        path: root.home + "/.config/quickshell/launcher-phrases.json"
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.about = d.actions || {}
                root.appPhrases = d.apps || {}
                root.keyPhrases = d.shortcuts || {}
            } catch (e) { console.warn("launcher-phrases.json:", e) }
        }
    }

    // niri's binds, read from its config: "Mod+Shift+F  Fullscreen Window". Enter runs the bound
    // action through `niri msg action` (it acts on the window you were in: the launcher never takes window focus).
    FileView {
        id: niriConf
        path: root.home + "/.config/niri/config.kdl"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.binds = root.parseBinds(text())
    }
    function parseBinds(text) {
        const out = []
        let inside = false
        for (const raw of text.split("\n")) {
            const line = raw.replace(/^\s+/, "")
            if (!inside) { if (/^binds\s*\{/.test(raw)) inside = true; continue }
            if (/^\}/.test(raw)) break
            if (line.startsWith("//")) continue
            const m = line.match(/^([A-Za-z0-9_+]+)\s*([^{]*)\{\s*(.*?)\s*;?\s*\}\s*$/)
            if (!m) continue
            const t = m[2].match(/hotkey-overlay-title=(?:"((?:[^"\\]|\\.)*)"|(null))/)
            if (t && t[2]) continue
            const toks = []
            const re = /"((?:[^"\\]|\\.)*)"|(\S+)/g
            let k
            while ((k = re.exec(m[3])) !== null) toks.push(k[1] !== undefined ? k[1].replace(/\\(.)/g, "$1") : k[2])
            if (!toks.length) continue
            const action = toks[0], args = toks.slice(1)
            const pos = args.filter(a => !/^[a-z-]+=/.test(a))
            const props = []
            args.filter(a => /^[a-z-]+=/.test(a)).forEach(a => props.push("--" + a.split("=")[0], a.split("=").slice(1).join("=")))
            const cmd = action === "spawn" ? ["niri", "msg", "action", "spawn", "--", ...pos]
                      : action === "spawn-sh" ? ["niri", "msg", "action", "spawn-sh", "--", pos.join(" ")]
                      : ["niri", "msg", "action", action, ...props, ...(pos.length ? ["--", ...pos] : [])]
            const title = t ? t[1] : action === "spawn" || action === "spawn-sh" ? "Run " + pos.join(" ")
                        : (action + " " + pos.join(" ")).replace(/-/g, " ").trim().replace(/^./, c => c.toUpperCase())
            out.push({ combo: m[1], title: title, cmd: cmd })
        }
        return out
    }
    function shortcutItems() {
        const merged = {}
        for (const a of actions()) for (const k of a.aliases) merged[k] = true
        // several binds running the same thing (Mod+Left, Mod+H, Mod+WheelScrollUp) are one row,
        // named by the first keyboard combo in the config; the others are listed under it
        const groups = {}, order = []
        for (const b of binds) {
            if (merged["key:" + b.combo]) continue
            const sg = cmdSig(b.cmd)
            if (!groups[sg]) { groups[sg] = []; order.push(sg) }
            groups[sg].push(b)
        }
        return order.map(sg => {
            const g = groups[sg].slice().sort((x, y) => /Wheel|Mouse|Touchpad/.test(x.combo) - /Wheel|Mouse|Touchpad/.test(y.combo))
            const b = g[0], combos = g.map(x => x.combo)
            return { key: "key:" + b.combo, skey: "key:" + b.combo, kind: "shortcut", title: b.title, sig: sg,
                     sub: combos.slice(0, 3).map(c => c.replace(/\+/g, " + ")).join("   or   "), glyph: "󰌌", hint: "Run", tag: b.combo,
                     extra: combos, aliases: combos.slice(1).map(c => "key:" + c), doc: sem.docText("keyboard shortcut", b.title),
                     run: () => Quickshell.execDetached(b.cmd) }
        })
    }
    // "brightness 40", "set volume to 30%"
    function ruleItems(q) {
        let m = q.match(/^(?:set\s+)?(?:screen\s+)?(?:brightness|bright|backlight)\s*(?:to\s*)?(\d{1,3})\s*%?(?:\s+(?:for|in|while|during)\b.*)?$/)
        if (m) {
            const n = String(Math.max(1, Math.min(100, parseInt(m[1]))))
            return [{ key: "", kind: "rule", title: "Set brightness to " + n + "%", sub: "", glyph: "󰃟", hint: "Set", tag: "Brightness",
                      run: () => Quickshell.execDetached(["sh", "-c", 'brightnessctl -q set "$1%" && qs ipc call osd brightness "$1"', "sh", n]) }]
        }
        m = q.match(/^(?:set\s+)?(?:volume|vol|sound)\s*(?:to\s*)?(\d{1,3})\s*%?(?:\s+(?:for|in|while|during)\b.*)?$/)
        if (m) {
            const n = String(Math.min(150, parseInt(m[1])))
            return [{ key: "", kind: "rule", title: "Set volume to " + n + "%", sub: parseInt(n) > 100 ? "Above 100% can distort" : "", glyph: "󰕾",
                      hint: "Set", tag: "Volume",
                      run: () => Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", n + "%"]) }]
        }
        return []
    }

    function windowItems() {
        return windows.map(w => {
            const e = DesktopEntries.heuristicLookup(w.app_id || "")
            return { key: "", kind: "window", title: w.title || w.app_id, sub: e ? e.name : (w.app_id || ""),
                     image: e ? e.icon : "", glyph: "󰖯", hint: "Switch", tag: "Window", extra: [w.app_id, e ? e.name : ""],
                     focused: w.is_focused, ts: w.focus_timestamp ? w.focus_timestamp.secs * 1e9 + w.focus_timestamp.nanos : 0,
                     run: () => Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(w.id)]) }
        }).sort((a, b) => b.ts - a.ts)
    }
    function fileItem(path) {
        const name = path.split("/").pop()
        const dir = path.slice(0, path.length - name.length - 1)
        return { key: "", kind: "file", title: name, sub: dir.replace(home, "~"), glyph: /\.\w{1,5}$/.test(name) ? "󰈔" : "󰉋",
                 hint: "Open", alt: "Open folder", tag: "File", path: path,
                 run: () => Quickshell.execDetached(["xdg-open", path]),
                 runAlt: () => Quickshell.execDetached(["xdg-open", dir]) }
    }
    function clipItem(line) {
        const tab = line.indexOf("\t")
        const id = line.slice(0, tab), text = line.slice(tab + 1)
        const img = /^\[\[ binary data .* (png|jpe?g|webp|bmp|gif) /.test(text)
        return { key: "", skey: img ? "" : "clip:" + Qt.md5(text), doc: img ? "" : sem.docText("clipboard", text.slice(0, 300)),
                 kind: "clip", title: img ? "Image  " + text.replace(/^\[\[ binary data /, "").replace(/ \]\]$/, "") : text.trim(),
                 sub: "", glyph: img ? "󰋩" : "󰅍", thumb: img ? "file://" + home + "/.cache/clip-menu/" + id + ".png" : "",
                 hint: "Copy", tag: "Clipboard",
                 run: () => Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" | cliphist decode | wl-copy', "sh", line]) }
    }

    Process {
        id: winProc
        command: ["niri", "msg", "--json", "windows"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.windows = JSON.parse(text) } catch (e) { root.windows = [] } root.refresh() }
        }
    }
    Process {
        id: clipProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: { root.clips = text.split("\n").filter(l => l.includes("\t")).slice(0, 200); root.refresh(); root.indexAll() }
        }
    }
    FileView {
        id: recentView
        path: root.home + "/.local/share/recently-used.xbel"
        printErrors: false
        onLoaded: {
            const seen = {}, out = []
            const re = /<bookmark href="file:\/\/([^"]+)"[^>]*?modified="([^"]+)"/g
            let m
            const t = text()
            while ((m = re.exec(t)) !== null) {
                let p
                try { p = decodeURIComponent(m[1]) } catch (e) { continue }
                if (seen[p]) continue
                seen[p] = true
                out.push({ path: p, t: Date.parse(m[2]) })
            }
            root.recentFiles = out.sort((a, b) => b.t - a.t).slice(0, 40).map(x => x.path)
            root.refresh()
        }
    }
    // plocate (the system index, updated daily): files under $HOME, no hidden folders
    Timer {
        id: findDelay
        interval: 120
        onTriggered: {
            const q = root.fileQuery()
            if (q.length < 2) { root.foundFiles = []; root.foundFor = ""; root.refresh(); return }
            findProc.running = false
            findProc.term = q
            findProc.command = ["plocate", "-i", "-l", "400", "--", ...q.split(/\s+/).filter(w => w)]
            findProc.running = true
        }
    }
    Process {
        id: findProc
        property string term: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const q = findProc.term.toLowerCase()
                const first = q.split(/\s+/)[0]
                const hits = text.split("\n").filter(p => p.startsWith(root.home + "/") && !/\/\.|\/node_modules\/|\/__pycache__\//.test(p.slice(root.home.length)))
                // name matches first, then shorter paths
                const rank = p => { const n = p.split("/").pop().toLowerCase(); return (n.startsWith(first) ? 0 : n.includes(first) ? 1 : 2) * 1000 + p.length }
                root.foundFiles = hits.sort((a, b) => rank(a) - rank(b)).slice(0, 40)
                root.foundFor = findProc.term
                root.refresh()
            }
        }
    }
    function fileQuery() {
        const q = query.trim()
        if (/^[\/~]/.test(q)) return q.replace(/^[\/~]\/?/, "").trim()
        return sections[section].id === "files" || (sections[section].id === "all" && q.length >= 3) ? q : ""
    }

    // ---- search by meaning ----
    Semantic { id: sem }
    // embed whatever is new (first run: ~300 things, ~10 s in the background; later only changes)
    function indexAll() {
        const docs = apps().map(appItem).concat(actions(), shortcutItems(), clips.slice(0, 100).map(clipItem))
            .filter(d => d.skey && d.doc).map(d => ({ key: d.skey, text: d.doc }))
        // each example phrase of an action on its own: short query vs short phrase matches far
        // better than against the whole description. Short phrases also match noise a bit more
        // readily, hence the small penalty (keeps unrelated queries under the 0.68 cut).
        const phrases = (key, text) => {
            for (const ph of text.split(/[:,.]/).map(x => x.trim()).filter(x => x))
                docs.push({ key: key, text: sem.docText("none", ph), adj: phraseAdj })
        }
        for (const id in about) phrases("act:" + id, about[id])
        for (const key in appPhrases) phrases(key, appPhrases[key])
        for (const it of shortcutItems()) if (keyPhrases[it.sig]) phrases(it.skey, keyPhrases[it.sig])
        sem.index(docs)
    }
    function semEligible(raw, sec) {
        // a phrase, or one longer word: on a short single word ("frfx") the nearest meanings are noise
        return (raw.includes(" ") ? raw.length >= 4 : raw.length >= 5) && !/^[=>?\/~]/.test(raw) && calc(raw) === null && ruleItems(raw.toLowerCase()).length === 0
            && (sec === "all" || sec === "apps" || sec === "actions" || sec === "clipboard")
    }
    // keep the close calls only: above the noise floor and near the best
    function semFilter(res, raw) {
        const hits = {}
        if (!res.length) return hits
        const best = res[0].cos, min = raw.trim().includes(" ") ? semMin : semMin1
        res.filter(r => r.cos >= min && r.cos >= best - semWindow).slice(0, 10).forEach(r => hits[r.key] = r.cos)
        return hits
    }
    Timer {
        id: semDelay
        interval: 90
        onTriggered: {
            const raw = root.query.trim()
            if (!root.semEligible(raw, root.sections[root.section].id)) return
            sem.search(raw, res => {
                if (root.query.trim() !== raw || !res.length) return
                root.semHits = root.semFilter(res, raw)
                root.semFor = raw
                root.refresh()
            })
        }
    }
    // cosine 0.68 -> 400 (a weak substring match), 0.76 -> 600, 0.84 -> 800 (a word-start match)
    function semScore(c) { return Math.min(850, 400 + (c - 0.68) * 2500) }

    // ---- building the list ----
    onQueryChanged: { current = 0; findDelay.restart(); semHits = {}; semDelay.restart(); refresh() }
    function refresh() {
        if (!want) return
        const raw = query.trim()
        items = compute(raw, sections[section].id, semFor === raw ? semHits : {}, false)
        if (current >= items.length) current = items.length - 1
        if (debug) console.warn("launcher [" + raw + "] sem for [" + semFor + "]: " + items.slice(0, 10).map(it =>
            it.title + " = " + Math.round(it.score || 0) + (it.skey && semHits[it.skey] !== undefined ? " (cos " + semHits[it.skey].toFixed(2) + ")" : "")).join(" | "))
    }
    // the result list for a query: also used headless (IPC `rank`), so it reads no UI state.
    // hits: semantic key -> cosine. neutral: ignore your usage history (frecency, learned picks).
    function compute(raw, sec, hits, neutral) {
        let q = raw.toLowerCase()
        let out = []
        const frec = key => neutral ? 0 : frecency(key)

        // prefixes
        if (raw.startsWith(">")) {
            const cmd = raw.slice(1).trim()
            return cmd ? [{ key: "", kind: "cmd", title: cmd, sub: "Run in a terminal (Ctrl+Enter: without one)", glyph: "", hint: "Run",
                            alt: "Run silently", tag: "Command",
                            run: () => Quickshell.execDetached(["kitty", "-o", "hide_window_decorations=yes", "--hold", "sh", "-c", cmd]),
                            runAlt: () => Quickshell.execDetached(["sh", "-c", cmd]) }]
                       : [{ key: "", kind: "hint", title: "Type a shell command", sub: "", glyph: "", tag: "" }]
        }
        if (raw.startsWith("?")) return [webItem(raw.slice(1).trim())]
        if (raw.startsWith("=")) return [calcItem(raw, calc(raw))]
        if (/^[\/~]/.test(raw)) { sec = "files"; q = fileQuery().toLowerCase() }

        const scored = (list, base) => {
            const res = []
            for (const it of list) {
                if (!q) { res.push(Object.assign(it, { score: base + 40 * Math.log2(1 + frec(it.key)), hits: [] })); continue }
                let m = matchItem(q, it.title, it.extra)
                if (it.keys && it.keys.includes(q)) m = { score: 1100, hits: m ? m.hits : [] }
                const c = it.skey ? hits[it.skey] : undefined
                if (c !== undefined && (!m || semScore(c) > m.score)) m = { score: semScore(c), hits: m ? m.hits : [] }
                if (!m) continue
                let s = m.score + base + 60 * Math.log2(1 + frec(it.key))
                if (!neutral && it.key && picks[q] === it.key) s += 2000
                res.push(Object.assign(it, { score: s, hits: m.hits, cos: c }))
            }
            return res.sort((a, b) => b.score - a.score)
        }

        if (sec === "all") {
            const c = q ? calc(raw) : null
            if (c !== null) out.push(calcItem(raw, c))
            out = out.concat(ruleItems(q))
            if (!q) {
                // suggestions: what you use most, then the open windows
                const used = scored(apps().map(appItem).concat(actions()), 0).filter(it => frec(it.key) > 0).slice(0, 6)
                out = out.concat(used.length ? used : scored(apps().map(appItem), 0).sort((a, b) => a.title.localeCompare(b.title)).slice(0, 6))
                out = out.concat(windowItems().filter(w => !w.focused).slice(0, 6))
            } else {
                const appActs = q.length >= 3 ? desktopActions() : []
                let mixed = scored(apps().map(appItem), 0)
                    .concat(scored(actions(), -20))
                    .concat(scored(windowItems(), -40))
                    .concat(scored(shortcutItems(), -60))
                    .concat(scored(appActs, -120))
                mixed.sort((a, b) => b.score - a.score)
                out = out.concat(mixed.slice(0, 30))
                // a few files too, but only where every word starts a word of the name ("too loud"
                // must not find "car-too-n_and_c-loud-s"); the Files section shows all of them
                if (foundFor && foundFor.toLowerCase() === fileQuery().toLowerCase()) {
                    const words = q.split(/\s+/).filter(w => w)
                    const starts = n => words.every(w => new RegExp("(^|[^a-z0-9])" + w.replace(/[^a-z0-9]/g, "\\$&")).test(n.toLowerCase()))
                    out = out.concat(foundFiles.filter(f => starts(f.split("/").pop())).slice(0, 4).map(fileItem))
                }
            }
        } else if (sec === "apps") {
            out = q ? scored(apps().map(appItem), 0).concat(scored(desktopActions(), -120)).sort((a, b) => b.score - a.score)
                    : scored(apps().map(appItem), 0).sort((a, b) => (b.score - a.score) || a.title.localeCompare(b.title))
        } else if (sec === "windows") {
            out = q ? scored(windowItems(), 0) : windowItems()
        } else if (sec === "actions") {
            out = ruleItems(q).concat(q ? scored(actions(), 0).concat(scored(shortcutItems(), -60)).sort((a, b) => b.score - a.score)
                                        : actions().concat(shortcutItems()))
        } else if (sec === "files") {
            if (!q) out = recentFiles.map(fileItem)
            else if (foundFor) out = foundFiles.map(fileItem)
            if (q && !out.length) out = [{ key: "", kind: "hint", title: findProc.running || findDelay.running ? "Searching…" : "No files found",
                                           sub: "", glyph: "󰍉", tag: "" }]
        } else if (sec === "clipboard") {
            out = clips.map(clipItem)
            if (q) out = scored(out, 0)
        }

        if (raw && (sec === "all" || sec === "apps")) out.push(webItem(raw))
        if (!out.length) out = [{ key: "", kind: "hint", title: sec === "clipboard" ? "Clipboard history is empty" : "Nothing found", sub: "", glyph: "󰍉", tag: "" }]
        return out
    }

    // ---- headless testing (no window): see the test harness in the dotfiles notes ----
    // rank: the top results for a query, as JSON. vec = the query's embedding, numbers joined by ";"
    // (qs ipc splits a JSON array into separate arguments). The caller embeds "task: search result | query: " + lower-cased query; "" = no semantic part.
    function rankJson(q, sec, vec) {
        const raw = q.trim()
        let hits = {}
        if (!Object.keys(sem.keyHash).length) indexAll()   // after a reload; vectors come from the cache
        if (vec && semEligible(raw, sec)) hits = semFilter(sem.scoreVec(sem.cut(vec.split(";").map(Number))), raw)
        return JSON.stringify(compute(raw, sec, hits, true).slice(0, 8).map(it =>
            ({ key: it.skey || it.key || "", aliases: it.aliases || [], kind: it.kind, title: it.title, score: Math.round(it.score || 0), cos: it.cos })))
    }
    function catalogJson() {
        const ab = it => ({ key: it.key, kind: it.kind, title: it.title, sub: it.sub || "", keys: it.keys || [], sig: it.sig,
                            about: it.kind === "action" ? (about[it.key.slice(4)] || "") : undefined })
        return JSON.stringify(apps().map(appItem).concat(actions(), shortcutItems()).map(ab))
    }

    function desktopActions() {
        const out = []
        for (const e of apps())
            for (const a of e.actions || [])
                out.push({ key: "app:" + e.id + ":" + a.id, kind: "app", title: a.name, sub: e.name, image: a.icon || e.icon, glyph: "󰣆",
                           hint: "Open", tag: e.name, extra: [e.name + " " + a.name], run: () => a.execute() })
        return out
    }
    function calcItem(raw, r) {
        return { key: "", kind: "calc", title: r === null ? "…" : r, sub: raw.replace(/^=/, "").trim() || "Type an expression, or e.g. 5 km in mi",
                 glyph: "󰃬", hint: "Copy", tag: "Calculator",
                 run: () => { if (r !== null) Quickshell.execDetached(["wl-copy", "--", r.replace(/ [a-z]+$/, "")]) } }
    }
    function webItem(s) {
        return { key: "", kind: "web", title: s ? "Search the web for “" + s + "”" : "Type to search the web", sub: s ? "DuckDuckGo" : "",
                 glyph: "󰖟", hint: "Search", tag: "Web",
                 run: () => { if (s) Quickshell.execDetached(["xdg-open", root.webSearch + encodeURIComponent(s)]) } }
    }

    function activate(i, alt) {
        const it = items[i]
        if (!it || !it.run) return
        remember(it)
        hide()
        if (alt && it.runAlt) it.runAlt()
        else it.run()
    }

    // highlight the matched characters (the text is escaped first)
    function marked(s, hits) {
        const esc = c => c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : c
        if (!hits || !hits.length) return s.split("").map(esc).join("")
        const set = {}
        hits.forEach(h => set[h] = true)
        let out = ""
        for (let i = 0; i < s.length; i++)
            out += set[i] ? "<font color=\"" + Theme.wsPill + "\">" + esc(s[i]) + "</font>" : esc(s[i])
        return out
    }

    // ---- the windows ----
    // click catcher: everything around the launcher (no blur: it has no layer-rule)
    PanelWindow {
        screen: root.screen
        visible: root.want
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "launcher-catcher"
        WlrLayershell.layer: WlrLayer.Top
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: root.hide()
        }
    }

    PanelWindow {
        id: win
        screen: root.screen
        visible: root.want || shut.running
        readonly property int rowH: 44
        readonly property int rows: 8
        anchors { top: true }
        margins { top: Math.round((screen ? screen.height : 960) * 0.16) }
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 640
        implicitHeight: 12 + 48 + 34 + rows * rowH + 12
        color: "transparent"
        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.want ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusLarge
            color: Theme.barBg
            border.color: Theme.barBorder
            border.width: 1
            opacity: 0.4 + 0.6 * root.open
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: 12
            opacity: root.open
            transform: Translate { y: (1 - root.open) * -4 }

            // the search field
            Item {
                id: head
                width: parent.width
                height: 48
                Text {
                    id: lens
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.query.startsWith(">") ? "" : root.query.startsWith("=") ? "󰃬" : root.query.startsWith("?") ? "󰖟" : "󰍉"
                    color: Theme.fgTitle
                    font { family: Theme.iconFont; pixelSize: 20 }
                }
                TextInput {
                    id: field
                    x: 44
                    width: parent.width - x - 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fgStrong
                    selectionColor: Theme.pillPress
                    selectedTextColor: Theme.fgStrong
                    font { family: Theme.font; pointSize: 17 * 0.75 }
                    focus: true
                    clip: true
                    onTextChanged: root.query = text
                    Text {
                        visible: !parent.text
                        text: "Search apps, windows, files, actions…"
                        color: Theme.fgMuted
                        font: parent.font
                    }

                    Keys.onPressed: ev => {
                        const ctrl = ev.modifiers & Qt.ControlModifier
                        const n = root.items.length
                        if (ev.key === Qt.Key_Escape) { root.hide() }
                        else if (ev.key === Qt.Key_Down || (ctrl && (ev.key === Qt.Key_N || ev.key === Qt.Key_J))) { root.current = (root.current + 1) % n }
                        else if (ev.key === Qt.Key_Up || (ctrl && (ev.key === Qt.Key_P || ev.key === Qt.Key_K))) { root.current = (root.current - 1 + n) % n }
                        else if (ev.key === Qt.Key_PageDown) { root.current = Math.min(n - 1, root.current + win.rows) }
                        else if (ev.key === Qt.Key_PageUp) { root.current = Math.max(0, root.current - win.rows) }
                        else if (ev.key === Qt.Key_Tab) { root.setSection(root.section + 1) }
                        else if (ev.key === Qt.Key_Backtab) { root.setSection(root.section - 1) }
                        else if (ctrl && ev.key >= Qt.Key_1 && ev.key <= Qt.Key_6) { root.setSection(ev.key - Qt.Key_1) }
                        else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { root.activate(root.current, ctrl) }
                        else return
                        ev.accepted = true
                    }
                }
            }

            // sections
            Row {
                id: tabs
                y: head.height
                x: 6
                height: 34
                spacing: 2
                Repeater {
                    model: root.sections
                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool on: root.section === index
                        anchors.verticalCenter: parent.verticalCenter
                        height: 24
                        width: lbl.implicitWidth + 20
                        radius: height / 2
                        color: on ? Theme.pillPress : tabMouse.containsMouse ? Theme.pillHover : Theme.clear(Theme.pillHover)
                        Behavior on color { ColorAnimation { duration: Theme.hoverIn } }
                        Text {
                            id: lbl
                            anchors.centerIn: parent
                            text: modelData.label
                            color: on ? Theme.fgStrong : Theme.fgMuted
                            font { family: Theme.font; pointSize: 12 * 0.75; weight: on ? Font.DemiBold : Font.Normal }
                        }
                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.setSection(index); field.forceActiveFocus() }
                        }
                    }
                }
            }
            Text {
                anchors { right: parent.right; rightMargin: 10; verticalCenter: tabs.verticalCenter }
                text: "Ctrl 1–6"
                color: Theme.fgMuted
                opacity: 0.7
                font { family: Theme.font; pointSize: 11 * 0.75 }
            }
            Rectangle {
                y: head.height + tabs.height - 1
                width: parent.width
                height: 1
                color: Theme.barBorder
            }

            ListView {
                id: list
                y: head.height + tabs.height + 4
                width: parent.width
                height: parent.height - y
                clip: true
                model: root.items
                currentIndex: root.current
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === root.current
                    width: list.width
                    height: win.rowH
                    radius: Theme.radiusSmall
                    color: sel ? Theme.pillHover : Theme.clear(Theme.pillHover)

                    // icon: app icon, clipboard thumbnail, or a glyph
                    Item {
                        id: ico
                        x: 8
                        width: 28; height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property string src: row.modelData.thumb ? row.modelData.thumb
                            : row.modelData.image ? (row.modelData.image.startsWith("/") ? "file://" + row.modelData.image : Quickshell.iconPath(row.modelData.image, true)) : ""
                        Image {
                            id: img
                            anchors.fill: parent
                            source: ico.src
                            sourceSize: Qt.size(56, 56)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !img.visible
                            text: row.modelData.glyph || ""
                            color: Theme.fgTitle
                            font { family: Theme.iconFont; pixelSize: 18 }
                        }
                    }
                    Column {
                        x: 46
                        width: parent.width - x - tail.width - 20
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                            text: root.marked((row.modelData.title || "").replace(/\s+/g, " "), row.modelData.hits)
                            color: row.modelData.kind === "hint" ? Theme.fgMuted : Theme.fg
                            font { family: Theme.font; pointSize: (row.modelData.kind === "calc" ? 15 : 13) * 0.75; weight: row.modelData.kind === "calc" ? Font.DemiBold : Font.Normal }
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            elide: Text.ElideMiddle
                            text: row.modelData.sub || ""
                            color: Theme.fgMuted
                            font { family: Theme.font; pointSize: 11 * 0.75 }
                        }
                    }
                    // what kind of thing it is; on the selected row, what Enter does
                    Text {
                        id: tail
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: row.sel && row.modelData.hint ? row.modelData.hint + (row.modelData.alt ? "  ·  Ctrl ↵ " + row.modelData.alt : "  ↵") : (row.modelData.tag || "")
                        color: row.sel ? Theme.fgTitle : Theme.fgMuted
                        font { family: Theme.font; pointSize: 11 * 0.75 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        // the surface appearing under a resting pointer sends a move too: ignore that one
                        onPositionChanged: ev => {
                            const p = mapToGlobal(ev.x, ev.y)
                            if (root.lastPointer && (Math.abs(p.x - root.lastPointer.x) > 2 || Math.abs(p.y - root.lastPointer.y) > 2)) root.current = row.index
                            root.lastPointer = p
                        }
                        onClicked: ev => root.activate(row.index, ev.modifiers & Qt.ControlModifier)
                    }
                }
            }
        }
    }
}
