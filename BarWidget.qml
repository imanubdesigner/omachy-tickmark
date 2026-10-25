import QtQuick
import QtQuick.Effects
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar button for Tickmark. Owns the plugin's single IPC target and the icon;
// the list, the editor, the bin and the save file all live in Panel.qml, which
// is loaded eagerly so the list hydrates as soon as the shell starts rather
// than waiting for the first click.

BarWidget {
    id: root

    moduleName: "io.github.imanubdesigner.tickmark"

    // Moving a bar widget briefly overlaps the retiring instance with its
    // replacement; registering the IPC target immediately can collide with the
    // copy that has not been torn down yet, so wait a tick for the slot to clear.
    property bool ipcRegistrationReady: false

    readonly property var panel: panelLoader.item
    readonly property bool opened: panel ? panel.opened === true : false
    // Kept as a plain property and refreshed from Panel's change signal:
    // nested reads through a `var`-typed panel are not always re-evaluated
    // by QML bindings when its JS array is replaced.
    property int itemCount: 0

    function syncCount() {
        itemCount = panel && panel.items ? panel.items.length : 0
    }

    // Bar icon: a dimmed outlined checkbox when the list is empty, then a box
    // with the number of open todos inside it (1 to 9, tinted with the accent
    // color), and a "9+" box beyond that. Same width for every glyph, so the
    // bar never shifts.
    readonly property var countGlyphs: ["󰄵", "󰎤", "󰎧", "󰎪", "󰎭", "󰎱", "󰎳", "󰎶", "󰎹", "󰎼", "󰎿"]
    readonly property string iconGlyph: countGlyphs[Math.min(itemCount, 10)]

    // Forwarded so opening another widget's popup closes this one cleanly.
    readonly property bool popoutSwitchClosing: panel ? panel.popoutSwitchClosing === true : false

    function injectPanel() {
        var target = panelLoader.item
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("settings" in target) target.settings = root.settings
        if ("anchorItem" in target) target.anchorItem = button
        if ("hostWidget" in target) target.hostWidget = root
    }

    function open() { if (panel) panel.open() }
    function close() { if (panel) panel.close() }
    function togglePanel() { if (panel) panel.toggle() }
    function closeForPopoutSwitch() { if (panel) panel.closeForPopoutSwitch() }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onPanelChanged: syncCount()
    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Connections {
        target: root.panel
        function onItemsChanged() { root.syncCount() }
    }

    Component.onCompleted: ipcRegistrationTimer.start()

    Timer {
        id: ipcRegistrationTimer
        interval: 100
        onTriggered: root.ipcRegistrationReady = true
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            root.syncCount()
            // The bar assigns `bar` and `settings` across two ticks on first mount;
            // a second pass catches whichever landed after the loader completed.
            Qt.callLater(function() { root.injectPanel(); root.syncCount() })
        }
    }

    IpcHandler {
        enabled: root.ipcRegistrationReady
        target: root.moduleName

        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.togglePanel() }

        // `omarchy-shell io.github.imanubdesigner.tickmark add "Buy milk" "Semi-skimmed"`.
        function add(name: string, description: string): string {
            if (!root.panel) return "unavailable"
            return root.panel.addItem(name, description)
        }

        // `omarchy-shell io.github.imanubdesigner.tickmark edit <id> "New title" "New description"`.
        function edit(id: string, name: string, description: string): string {
            if (!root.panel) return "unavailable"
            return root.panel.updateItem(id, name, description)
        }

        // `omarchy-shell io.github.imanubdesigner.tickmark done <id>` ticks an item
        // off into the bin, exactly like clicking its checkbox.
        function done(id: string): string {
            if (!root.panel) return "unavailable"
            return root.panel.completeItem(id)
        }

        // `omarchy-shell io.github.imanubdesigner.tickmark restore <id>` brings a
        // ticked-off item back from the bin.
        function restore(id: string): string {
            if (!root.panel) return "unavailable"
            return root.panel.restoreItem(id)
        }

        // `omarchy-shell io.github.imanubdesigner.tickmark remove <id>`.
        function remove(id: string): string {
            if (!root.panel) return "unavailable"
            root.panel.deleteItem(id)
            return "ok"
        }

        // `omarchy-shell io.github.imanubdesigner.tickmark list` prints the open
        // todos as JSON: [{"id": "...", "name": "...", "description": "..."}].
        function list(): string {
            if (!root.panel) return "[]"
            return Model.toJson(root.panel.items)
        }

        function status(): string {
            return root.itemCount + " todo" + (root.itemCount === 1 ? "" : "s")
        }
    }

    // The button is the only item in the widget, exactly like the stock
    // widgets: WidgetButton owns the click, the hover and the hand cursor.
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.iconGlyph
        // Half opacity is fine for input; only a fully transparent item stops
        // receiving the mouse, so the hand cursor is unaffected.
        opacity: root.itemCount > 0 ? 1 : 0.55

        // `active` would paint the button in the theme's red ("urgent"), so the
        // tint is applied to the rendered button instead. A layer effect only
        // changes how the pixels are drawn: clicks, hover and the hand cursor
        // still belong to WidgetButton. Accent follows every Omarchy theme.
        layer.enabled: root.itemCount > 0
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: Commons.Color.accent
        }
        fontSize: Style.bar.iconFont
        fixedWidth: root.vertical ? -1 : Style.bar.iconSlot
        fixedHeight: root.vertical ? Style.bar.iconSlot : -1
        tooltipText: root.itemCount > 0
            ? root.itemCount + " todo" + (root.itemCount === 1 ? "" : "s")
            : "Tickmark Todo"
        onPressed: function(pressedButton) {
            if (pressedButton === Qt.LeftButton) root.togglePanel()
        }
    }
}
