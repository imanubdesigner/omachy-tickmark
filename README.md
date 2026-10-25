# Tickmark Todo

**A tiny todo list that lives in your Omarchy bar.**

> Tickmark Todo was inspired by [omarchy-checklist-todo](https://github.com/tathagat11/omarchy-checklist-todo) by [tathagat11](https://github.com/tathagat11). Thank you for the idea, and for a plugin and README that were a pleasure to learn from.

A checklist for the [Omarchy](https://omarchy.org/) bar. Add an item, read it, tick it off, and bring it back from the bin if you ticked it by mistake. No accounts, no sync, nothing to configure.

<!-- Add preview.png / preview.gif to the repo root and uncomment:
![Tickmark Todo panel](preview.png)
![Tickmark Todo demo](preview.gif)
-->

Use it as a general checklist or a lightweight todo list. The whole plugin is three small files, and your data is a plain JSON file you can read, back up, or edit by hand.

**Empty list:**

![tickmark_nolist_preview.png](/home/manu/Projects/omarchy-tickmark/tickmark_nolist_preview.png)

**Three item:**

![tickmark_preview.webp](/home/manu/Projects/omarchy-tickmark/tickmark_preview.webp)

## Features

- **Add in a keystroke**: type a name and an optional description. New items go on top.
- **One-line list**: just names, each with a checkbox beside it.
- **Details on demand**: click an item to read its description.
- **Edit anything**: right-click an item to change its title and description.
- **Drag to reorder**: press and hold an item, then drag it where you want it.
- **Tick to finish, undo if you slip**: ticking an item moves it to a bin. From there you can restore it or delete it for good.
- **Count in the icon**: the bar icon shows how many todos are open, from 1 to 9 and then 9+, tinted with your theme's accent color. With an empty list it turns into a dimmed outlined checkbox. Hover it for the exact number.
- **Scriptable**: list, add, edit and remove items from the terminal via IPC.
- **Zero dependencies**: no scripts, no services, no network.

<img src="/home/manu/.config/marktext/images/c493405a5b1125757ff4f43d58819b7e51c70c4a.gif" title="" alt="" width="494" />

## Installation

```
omarchy plugin add https://github.com/imanubdesigner/omarchy-tickmark --enable
```

Omarchy will ask which bar section to place it in: **left**, **center** or **right**.

### From a local clone

```
mkdir -p ~/.config/omarchy/plugins/io.github.imanubdesigner.tickmark
cp manifest.json BarWidget.qml Panel.qml Model.js \
  ~/.config/omarchy/plugins/io.github.imanubdesigner.tickmark/
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.imanubdesigner.tickmark --section right
```

## Usage

Click the checkbox icon in the bar to open the list.

| Action          | Mouse                                               |
| --------------- | --------------------------------------------------- |
| New item        | Click `+`                                           |
| Open an item    | Click its name                                      |
| Edit an item    | Right-click its name                                |
| Reorder         | Press and hold an item, drag it up or down, release |
| Finish an item  | Click its checkbox                                  |
| Open the bin    | Click the bin icon in the panel header              |
| Restore         | Click the undo arrow in the bin                     |
| Delete for good | Click the bin icon on an item in the bin            |
| Save            | Click **Save**                                      |
| Close           | Click outside                                       |

Right after you tick an item, an undo line appears under the list. The bin icon in the panel header is always there, and like a desktop trash can it is drawn empty or full. The bin keeps the last 50 finished items, and **Empty bin** clears it.

Keyboard: `n` or `+` starts a new item, `Enter` moves from name to description and then saves, `Esc` goes back or closes the panel.

Like every bar widget, it can be moved and reordered:

```
omarchy bar move io.github.imanubdesigner.tickmark --section left
omarchy plugin disable io.github.imanubdesigner.tickmark
```

## IPC

The plugin exposes an IPC target for scripting:

```
# Add an item
omarchy-shell io.github.imanubdesigner.tickmark add "Buy milk" "Semi-skimmed"

# Edit an item
omarchy-shell io.github.imanubdesigner.tickmark edit <id> "New title" "New description"

# List the open items as JSON
omarchy-shell io.github.imanubdesigner.tickmark list

# How many items are open
omarchy-shell io.github.imanubdesigner.tickmark status

# Tick an item off into the bin (same as clicking its checkbox)
omarchy-shell io.github.imanubdesigner.tickmark done <id>

# Bring an item back from the bin
omarchy-shell io.github.imanubdesigner.tickmark restore <id>

# Delete an item for good by id (open list or bin)
omarchy-shell io.github.imanubdesigner.tickmark remove <id>
```

## Data

Your list is stored as plain JSON at:

```
~/.local/state/io.github.imanubdesigner.tickmark/todos.json
```

It holds two lists, `items` (open) and `bin` (finished). Files from earlier versions, which contain only the open list, are read without changes. Nothing leaves your machine. Delete the file to start over.

## Uninstall

```
omarchy plugin disable io.github.imanubdesigner.tickmark
omarchy plugin remove io.github.imanubdesigner.tickmark
```

Optionally delete your data:

```
rm -rf ~/.local/state/io.github.imanubdesigner.tickmark
```

## Development

Validate the manifest and lint the QML:

```
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
```

Edits under `~/.config/omarchy/plugins/` hot-reload on save.

## Roadmap

Ideas for later live in [ROADMAP.md](ROADMAP.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
