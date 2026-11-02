// The monitor's views and keys, in the order the key help lists them: a view key shows that view, c cycles through
// the views every 5 s, q quits.
export const OPT_KEYS = {
    E: {key: "e", opt: "efund"},
    I: {key: "i", opt: "ibc"},
    O: {key: "o", opt: "overview"},
    P: {key: "p", opt: "streams"},
    B: {key: "b", opt: "beacons"},
    W: {key: "w", opt: "wrkchains"},
    C: {key: "c", opt: "cycle"},
    Q: {key: "q", opt: "quit"},
}

// Which view is on screen, and whether the views are cycling.
export class Display {

    view = OPT_KEYS.O.key
    cycling = false
    #order = [OPT_KEYS.O, OPT_KEYS.P, OPT_KEYS.I, OPT_KEYS.E, OPT_KEYS.B, OPT_KEYS.W].map((o) => o.key)

    // Applies a key press. Returns true when the screen should be redrawn straight away.
    press(name) {
        if (this.#order.includes(name)) {
            this.cycling = false
            this.view = name
            return true
        }
        if (name === OPT_KEYS.C.key) {
            this.cycling = !this.cycling
        }
        if (name === OPT_KEYS.Q.key) {
            console.log("")
            process.exit()
        }
        return false
    }

    // Shows the next view, when cycling.
    advance() {
        if (this.cycling) {
            const view = this.#order.shift()
            this.view = view
            this.#order.push(view)
        }
    }
}
