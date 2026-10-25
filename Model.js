.pragma library

// Pure helpers for the todo list. No QML types in here so the file can be
// loaded as a shared library and tested with any JS runtime.
//
// The save file holds two lists: `items` (open todos) and `bin` (todos that
// were ticked off and can still be restored or deleted for good).

// How many ticked-off todos the bin keeps. The oldest ones fall off.
var BIN_LIMIT = 50

// Collapse whitespace (including newlines) and trim.
function squish(value) {
    return String(value === undefined || value === null ? "" : value)
        .replace(/\s+/g, " ")
        .trim()
}

function makeId() {
    return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

// Cleans one list: drops unreadable entries and duplicate ids. `seen` is
// shared between lists so an id is never used twice across the whole file.
function cleanList(list, withDoneAt, seen) {
    var out = []
    if (!Array.isArray(list)) return out

    for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        if (!entry || typeof entry !== "object") continue

        var name = squish(entry.name)
        if (name === "") continue

        var id = typeof entry.id === "string" && entry.id !== "" ? entry.id : makeId()
        if (seen[id]) id = makeId()
        seen[id] = true

        var item = { id: id, name: name, description: squish(entry.description) }
        if (withDoneAt) {
            item.doneAt = typeof entry.doneAt === "number" && isFinite(entry.doneAt) ? entry.doneAt : 0
        }
        out.push(item)
    }
    return out
}

// Accepts {"items": [...], "bin": [...]} or a bare array of items (the
// version 1 layout has no bin). Anything unreadable yields empty lists
// instead of throwing, so a corrupt file never breaks the bar.
function parse(raw) {
    var empty = { items: [], bin: [] }
    if (!raw || String(raw).trim() === "") return empty

    var data
    try {
        data = JSON.parse(raw)
    } catch (e) {
        return empty
    }

    var seen = {}
    var items = cleanList(Array.isArray(data) ? data : (data ? data.items : []), false, seen)
    var bin = cleanList(!Array.isArray(data) && data ? data.bin : [], true, seen)
    return { items: items, bin: bin.slice(0, BIN_LIMIT) }
}

function serialize(items, bin) {
    var seen = {}
    var data = {
        version: 2,
        items: cleanList(items, false, seen),
        bin: cleanList(bin, true, seen).slice(0, BIN_LIMIT)
    }
    return JSON.stringify(data, null, 2) + "\n"
}

// Plain-JSON view of a list for the IPC `list` command.
function toJson(items) {
    var out = []
    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        if (!it) continue
        out.push({ id: it.id, name: it.name, description: it.description || "" })
    }
    return JSON.stringify(out)
}
