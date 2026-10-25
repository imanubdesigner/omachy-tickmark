# Changelog

## 1.0.0

- Initial release: todo list in the Omarchy bar with name and description and right-click editing.
- Ticking an item moves it to a bin; from there it can be restored or deleted for good. The bin keeps the last 50 items.
- The bar icon shows the number of open todos (1 to 9, then 9+) inside the icon itself, so the widget keeps its width.
- New items are added on top of the list, and items can be reordered by pressing and holding them and dragging.
- The bar icon is a dimmed outlined checkbox when the list is empty; the bin icon is drawn empty or full.
- IPC commands: `add`, `edit`, `done`, `restore`, `remove`, `list` (JSON), `status`.
