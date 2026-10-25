import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The Tickmark panel: a list of todos, an editor (used both for new items
// and for editing existing ones), a read-only detail view, and a bin that
// holds ticked-off todos until they are restored or deleted for good. The panel is
// a nested bar-widget surface, so BarWidget.qml owns the IPC target and
// lifecycle forwarding while this file owns the data, the views, and the
// save file.

Panel {
    id: root

    moduleName: "io.github.imanubdesigner.tickmark"
    ipcTarget: "io.github.imanubdesigner.tickmark"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null

    readonly property var barIdentity: hostWidget || root
    readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
    readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property color dimForeground: Qt.darker(contentForeground, 1.5)

    // ---- state. `items` is replaced wholesale on every mutation so bindings
    // in the views re-evaluate without a model class.
    property var items: []
    property var bin: []                  // ticked-off todos, newest first
    property string view: "list"          // "list" | "compose" | "detail" | "bin"
    property string selectedId: ""
    property bool loaded: false
    // Last item ticked off in this session, offered for a quick undo in the list.
    property string lastDoneId: ""
    property string lastDoneName: ""

    // Drag-to-reorder state, shared by the rows of the list. `dragFrom` is
    // the index the held row started at, `dropTo` the index it would land on
    // if released now, and `dragDelta` how far the pointer moved it, in pixels.
    property string dragId: ""
    property int dragFrom: -1
    property int dropTo: -1
    property real dragDelta: 0

    // Editing: when `editingId` is set, the compose view edits that item
    // instead of creating a new one. `returnView` is where Save/Cancel lands.
    property string editingId: ""
    property string returnView: "list"

    readonly property bool editing: editingId !== ""

    readonly property var selectedItem: findItem(selectedId)
    readonly property var detailItem: selectedItem || ({})
    readonly property string countLabel: items.length + " item" + (items.length === 1 ? "" : "s")

    function findInBin(id) {
        if (id === "") return null
        for (var i = 0; i < bin.length; i++)
            if (bin[i] && bin[i].id === id) return bin[i]
        return null
    }

    function findItem(id) {
        if (id === "") return null
        for (var i = 0; i < items.length; i++)
            if (items[i] && items[i].id === id) return items[i]
        return null
    }

    // Coming back to a shut panel always lands on the list, whatever tab was
    // left showing.
    onOpenedChanged: {
        if (!opened) {
            view = "list"
            selectedId = ""
            editingId = ""
            returnView = "list"
            lastDoneId = ""
            endDrag(false)
        }
    }

    function focusNameField() {
        if (nameField) nameField.forceActiveFocus()
    }

    function focusKeyCatcher() {
        Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }

    // ---- persistence. Same FileView + atomicWrites + guarded-before-write
    // pattern the first-party notifications service uses.
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/io.github.imanubdesigner.tickmark/"
    readonly property string savePath: stateDir + "todos.json"

    function applyLoaded(raw) {
        var next = Model.parse(raw)
        // Skip no-op updates so this instance's own write (and the directory
        // reload it provokes) does not churn the views on every save.
        if (loaded && Model.serialize(next.items, next.bin) === Model.serialize(items, bin)) return
        items = next.items
        bin = next.bin
        loaded = true
    }

    function saveNow() {
        // Never write before reading: a save issued in the gap between
        // construction and the file landing would clobber the list we are
        // about to restore.
        if (!loaded) return
        saveFile.setText(Model.serialize(items, bin))
    }

    function scheduleSave() { saveTimer.restart() }

    function reloadFromDisk() {
        saveFile.reload()
        // Start (or restart) the directory watch now the directory exists.
        stateDirWatch.reload()
    }

    Process {
        id: ensureDirProc
        command: ["mkdir", "-p", root.stateDir]
        onExited: Qt.callLater(root.reloadFromDisk)
    }

    FileView {
        id: saveFile
        path: root.savePath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyLoaded(text())
        // First run: no file yet. FileView reports that as a load failure, and
        // without this branch `loaded` stays false forever and saving is a no-op.
        onLoadFailed: if (!root.loaded) root.applyLoaded("")
    }

    // Watch the directory rather than the file: the file does not exist on the
    // first run, and atomic writes replace its inode, so a file watch would go
    // quiet after the first write. The directory always exists and sees every
    // rewrite, which is what keeps both monitors' panels in step.
    FileView {
        id: stateDirWatch
        path: root.stateDir
        watchChanges: true
        printErrors: false
        onFileChanged: dirReloadTimer.restart()
    }

    Timer {
        id: dirReloadTimer
        interval: 150
        repeat: false
        onTriggered: if (root.loaded) saveFile.reload()
    }

    Timer {
        id: saveTimer
        interval: 300
        repeat: false
        onTriggered: root.saveNow()
    }

    Component.onCompleted: ensureDirProc.running = true

    // ---- operations
    function addItem(name, description) {
        var cleanName = Model.squish(name)
        if (cleanName === "") return "empty"
        // New items go on top of the list.
        var next = items.slice()
        next.unshift({ id: Model.makeId(), name: cleanName, description: Model.squish(description) })
        items = next
        scheduleSave()
        return cleanName
    }

    // Moves one open item to a new position in the list.
    function moveItem(id, toIndex) {
        var from = -1
        for (var i = 0; i < items.length; i++)
            if (items[i] && items[i].id === id) { from = i; break }
        if (from < 0) return "missing"
        var target = Math.max(0, Math.min(items.length - 1, toIndex))
        if (target === from) return "ok"
        var next = items.slice()
        var moved = next.splice(from, 1)[0]
        next.splice(target, 0, moved)
        items = next
        scheduleSave()
        return "ok"
    }

    // Ends a drag. On commit the held item lands on the highlighted slot.
    function endDrag(commit) {
        var id = dragId
        var to = dropTo
        var from = dragFrom
        dragId = ""
        dragFrom = -1
        dropTo = -1
        dragDelta = 0
        if (commit && id !== "" && to !== from) moveItem(id, to)
    }

    // Replaces title and description of one item, keeping its id and position.
    function updateItem(id, name, description) {
        var cleanName = Model.squish(name)
        if (cleanName === "") return "empty"
        var next = []
        var found = false
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            if (it && it.id === id) {
                next.push({ id: id, name: cleanName, description: Model.squish(description) })
                found = true
            } else if (it) {
                next.push(it)
            }
        }
        if (!found) return "missing"
        items = next
        scheduleSave()
        return cleanName
    }

    // Ticking an item off moves it to the bin instead of destroying it.
    function completeItem(id) {
        var target = findItem(id)
        if (!target) return "missing"
        var next = []
        for (var i = 0; i < items.length; i++)
            if (items[i] && items[i].id !== id) next.push(items[i])
        var binned = bin.slice()
        binned.unshift({ id: target.id, name: target.name, description: target.description || "", doneAt: Date.now() })
        items = next
        bin = binned.slice(0, Model.BIN_LIMIT)
        if (selectedId === id) selectedId = ""
        lastDoneId = target.id
        lastDoneName = target.name
        scheduleSave()
        return "ok"
    }

    // Brings a ticked-off item back to the end of the open list.
    function restoreItem(id) {
        var target = null
        var nextBin = []
        for (var i = 0; i < bin.length; i++) {
            if (bin[i] && bin[i].id === id) target = bin[i]
            else if (bin[i]) nextBin.push(bin[i])
        }
        if (!target) return "missing"
        var next = items.slice()
        next.push({ id: target.id, name: target.name, description: target.description || "" })
        items = next
        bin = nextBin
        if (id === lastDoneId) lastDoneId = ""
        if (nextBin.length === 0 && view === "bin") backToList()
        scheduleSave()
        return "ok"
    }

    // Deletes for good, from the open list or from the bin.
    function deleteItem(id) {
        var next = []
        for (var i = 0; i < items.length; i++)
            if (items[i] && items[i].id !== id) next.push(items[i])
        var nextBin = []
        for (var j = 0; j < bin.length; j++)
            if (bin[j] && bin[j].id !== id) nextBin.push(bin[j])
        items = next
        bin = nextBin
        if (selectedId === id) selectedId = ""
        if (id === lastDoneId) lastDoneId = ""
        if (nextBin.length === 0 && view === "bin") backToList()
        scheduleSave()
    }

    function emptyBin() {
        bin = []
        lastDoneId = ""
        if (view === "bin") backToList()
        scheduleSave()
    }

    function openBin() {
        view = "bin"
        focusKeyCatcher()
    }

    function openDetail(id) {
        selectedId = id
        view = "detail"
    }

    function beginCompose() {
        editingId = ""
        returnView = "list"
        if (nameField) nameField.text = ""
        if (descriptionField) descriptionField.text = ""
        view = "compose"
        Qt.callLater(root.focusNameField)
    }

    // Right-click entry point. `from` is the view to return to afterwards.
    function beginEdit(id, from) {
        var target = findItem(id)
        if (!target) return
        editingId = id
        selectedId = id
        returnView = from === "detail" ? "detail" : "list"
        if (nameField) nameField.text = target.name
        if (descriptionField) descriptionField.text = target.description || ""
        view = "compose"
        Qt.callLater(root.focusNameField)
    }

    // Leaves the editor, whether it was composing or editing.
    function leaveEditor() {
        var target = editing ? returnView : "list"
        editingId = ""
        returnView = "list"
        view = target
        focusKeyCatcher()
    }

    function cancelCompose() { leaveEditor() }

    function saveCompose() {
        var result = editing
            ? updateItem(editingId, nameField.text, descriptionField.text)
            : addItem(nameField.text, descriptionField.text)

        if (result === "empty") {
            focusNameField()
            return
        }
        nameField.text = ""
        descriptionField.text = ""
        leaveEditor()
    }

    function backToList() {
        view = "list"
        focusKeyCatcher()
    }

    KeyboardPanel {
        id: panel

        anchorItem: root.anchorItem
        owner: root
        bar: root.bar
        open: root.opened
        centerOnBar: true
        focusTarget: keyCatcher

        contentWidth: panel.fittedContentWidth(Style.space(340))
        contentHeight: panel.fittedContentHeight(bodyColumn.implicitHeight, Style.space(520))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent

            // While an editor field is focused, keys belong to the field.
            blocked: nameField.activeFocus || descriptionField.activeFocus

            onCloseRequested: {
                if (root.view === "list") root.close()
                else if (root.view === "compose") root.cancelCompose()
                else root.backToList()
            }

            // `n` (or `+`) starts a new todo without reaching for the mouse.
            onTextKey: function(t) {
                if (root.view === "list" && (t === "n" || t === "N" || t === "+"))
                    root.beginCompose()
            }

            // Right-click anywhere on the detail view edits the open item.
            // Sits below the Flickable so it never steals clicks from rows.
            MouseArea {
                anchors.fill: parent
                z: -1
                enabled: root.view === "detail"
                acceptedButtons: Qt.RightButton
                onClicked: root.beginEdit(root.selectedId, "detail")
            }

            Flickable {
                id: scroll
                anchors.fill: parent
                contentWidth: width
                contentHeight: bodyColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: bodyColumn
                    width: scroll.width
                    spacing: Style.spacing.lg

                    // ============================================================ LIST
                    Column {
                        visible: root.view === "list"
                        width: parent.width
                        spacing: Style.spacing.md

                        Item {
                            width: parent.width
                            height: Math.max(listTitle.implicitHeight, addButton.implicitHeight)

                            Text {
                                id: listTitle
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Todos"
                                color: root.contentForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                            }

                            Text {
                                id: listCount
                                anchors.right: binButton.left
                                anchors.rightMargin: Style.spacing.lg
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.countLabel
                                color: root.dimForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.caption
                            }

                            PanelActionButton {
                                id: binButton
                                anchors.right: addButton.left
                                anchors.verticalCenter: parent.verticalCenter
                                // Like a desktop trash can: empty glyph when there is
                                // nothing inside, full glyph when there is.
                                iconText: root.bin.length > 0 ? "󰆴" : "󰛌"
                                tooltipText: root.bin.length > 0
                                    ? "Done (" + root.bin.length + ")"
                                    : "Done"
                                opacity: root.bin.length > 0 ? 1 : 0.5
                                foreground: root.contentForeground
                                fontFamily: root.contentFontFamily
                                onClicked: root.openBin()
                            }

                            PanelActionButton {
                                id: addButton
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                iconText: "󰐕"
                                tooltipText: "New todo"
                                foreground: root.contentForeground
                                fontFamily: root.contentFontFamily
                                onClicked: root.beginCompose()
                            }
                        }

                        Text {
                            visible: root.items.length === 0
                            width: parent.width
                            text: "Nothing here yet. Press + to add a todo."
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            topPadding: Style.spacing.md
                            bottomPadding: Style.spacing.md
                            color: root.dimForeground
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.body
                        }

                        Repeater {
                            model: root.items

                            delegate: Item {
                                id: rowItem
                                required property var modelData
                                required property int index

                                readonly property bool isDragged: root.dragId === modelData.id
                                // While another row is held, rows between its start and its
                                // target slide one step out of the way.
                                readonly property real shiftY: {
                                    if (root.dragId === "") return 0
                                    if (isDragged) return root.dragDelta
                                    var step = height + (parent ? (parent.spacing || 0) : 0)
                                    if (root.dragFrom < root.dropTo && index > root.dragFrom && index <= root.dropTo)
                                        return -step
                                    if (root.dragFrom > root.dropTo && index >= root.dropTo && index < root.dragFrom)
                                        return step
                                    return 0
                                }

                                z: isDragged ? 10 : 0
                                opacity: isDragged ? 0.92 : 1
                                transform: Translate {
                                    y: rowItem.shiftY
                                    Behavior on y {
                                        enabled: !rowItem.isDragged
                                        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                                    }
                                }

                                width: bodyColumn.width
                                height: Math.max(rowCheck.implicitHeight, rowTitle.implicitHeight) + Style.spacing.lg

                                property bool checkHovered: false
                                readonly property bool rowHovered: rowHover.containsMouse

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Style.cornerRadius
                                    color: (rowItem.rowHovered || rowItem.isDragged)
                                        ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                                        : "transparent"
                                }

                                // Declared before the checkbox so the checkbox's own handler
                                // sits on top and clicking the box ticks it off rather than opens.
                                // Left click opens the detail, right click edits.
                                MouseArea {
                                    id: rowHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: rowItem.isDragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    pressAndHoldInterval: 350

                                    // Press and hold the row with the left button to pick it up,
                                    // move up or down, release to drop it in its new place.
                                    property bool held: false
                                    property real pressY: 0

                                    onPressed: held = false
                                    onPressAndHold: function(mouse) {
                                        if (mouse.button !== Qt.LeftButton || root.items.length < 2) return
                                        held = true
                                        pressY = mapToItem(rowItem.parent, mouse.x, mouse.y).y
                                        root.dragId = rowItem.modelData.id
                                        root.dragFrom = rowItem.index
                                        root.dropTo = rowItem.index
                                        root.dragDelta = 0
                                    }
                                    onPositionChanged: function(mouse) {
                                        if (!held || root.dragId !== rowItem.modelData.id) return
                                        var step = rowItem.height + (rowItem.parent.spacing || 0)
                                        var y = mapToItem(rowItem.parent, mouse.x, mouse.y).y
                                        var lastIndex = root.items.length - 1
                                        var delta = Math.max(-root.dragFrom * step,
                                                             Math.min((lastIndex - root.dragFrom) * step, y - pressY))
                                        root.dragDelta = delta
                                        root.dropTo = Math.max(0, Math.min(lastIndex,
                                                               root.dragFrom + Math.round(delta / step)))
                                    }
                                    onReleased: { if (held) root.endDrag(true) }
                                    onCanceled: { if (held) root.endDrag(false) }

                                    onClicked: function(mouse) {
                                        if (held) return   // the release of a drag is not a click
                                        if (mouse.button === Qt.RightButton)
                                            root.beginEdit(rowItem.modelData.id, "list")
                                        else
                                            root.openDetail(rowItem.modelData.id)
                                    }
                                }

                                Text {
                                    id: rowCheck
                                    anchors.left: parent.left
                                    anchors.leftMargin: Style.spacing.lg
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰄱"
                                    // Ticking only moves the item to the bin, so the box
                                    // lights up in the accent colour under its own pointer.
                                    color: rowItem.checkHovered
                                        ? Commons.Color.accent
                                        : (rowItem.rowHovered ? root.contentForeground : root.dimForeground)
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.subtitle

                                    Behavior on color { ColorAnimation { duration: 80 } }

                                    // Left button only (the default), so a right-click on the
                                    // box falls through to the row and opens the editor.
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -Style.spacing.sm
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onContainsMouseChanged: rowItem.checkHovered = containsMouse
                                        onClicked: root.completeItem(rowItem.modelData.id)
                                    }
                                }

                                Text {
                                    id: rowTitle
                                    anchors.left: rowCheck.right
                                    anchors.leftMargin: Style.spacing.controlGap
                                    anchors.right: parent.right
                                    anchors.rightMargin: Style.spacing.lg
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: root.contentForeground
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.body
                                }
                            }
                        }

                        // Immediate feedback after ticking an item, with a one-click undo.
                        Item {
                            visible: root.lastDoneId !== "" && root.findInBin(root.lastDoneId) !== null
                            width: parent.width
                            height: undoButton.implicitHeight

                            PanelActionButton {
                                id: undoButton
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                iconText: "󰕌"
                                tooltipText: "Undo"
                                foreground: root.contentForeground
                                fontFamily: root.contentFontFamily
                                onClicked: root.restoreItem(root.lastDoneId)
                            }

                            Text {
                                anchors.left: undoButton.right
                                anchors.leftMargin: Style.spacing.md
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Done: " + root.lastDoneName
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: root.dimForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.caption
                            }
                        }

                        Text {
                            visible: root.items.length > 0
                            width: parent.width
                            text: "Right-click to edit, hold to reorder"
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignLeft
                            color: root.dimForeground
                            opacity: 0.7
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }

                    // ================================================== COMPOSE / EDIT
                    Column {
                        visible: root.view === "compose"
                        width: parent.width
                        spacing: Style.spacing.md

                        Item {
                            width: parent.width
                            height: Math.max(composeTitle.implicitHeight, backFromCompose.implicitHeight)

                            PanelActionButton {
                                id: backFromCompose
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                iconText: "󰁍"
                                tooltipText: "Back"
                                foreground: root.contentForeground
                                fontFamily: root.contentFontFamily
                                onClicked: root.cancelCompose()
                            }

                            Text {
                                id: composeTitle
                                anchors.left: backFromCompose.right
                                anchors.leftMargin: Style.spacing.md
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.editing ? "Edit todo" : "New todo"
                                color: root.contentForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                            }
                        }

                        TextField {
                            id: nameField
                            width: parent.width
                            placeholderText: "Name"
                            foreground: root.contentForeground
                            font.family: root.contentFontFamily

                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Escape) {
                                    root.cancelCompose()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    descriptionField.forceActiveFocus()
                                    event.accepted = true
                                }
                            }
                        }

                        TextField {
                            id: descriptionField
                            width: parent.width
                            placeholderText: "Description"
                            foreground: root.contentForeground
                            font.family: root.contentFontFamily

                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Escape) {
                                    root.cancelCompose()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    root.saveCompose()
                                    event.accepted = true
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: saveRow.implicitHeight

                            Row {
                                id: saveRow
                                anchors.right: parent.right
                                spacing: Style.spacing.md

                                Button {
                                    text: "Cancel"
                                    foreground: root.contentForeground
                                    fontFamily: root.contentFontFamily
                                    onClicked: root.cancelCompose()
                                }

                                Button {
                                    text: "Save"
                                    bordered: true
                                    foreground: root.contentForeground
                                    fontFamily: root.contentFontFamily
                                    onClicked: root.saveCompose()
                                }
                            }
                        }
                    }

                    // ========================================================== DETAIL
                    Column {
                        visible: root.view === "detail"
                        width: parent.width
                        spacing: Style.spacing.md

                        Item {
                            width: parent.width
                            height: Math.max(detailTitle.implicitHeight, backFromDetail.implicitHeight)

                            PanelActionButton {
                                id: backFromDetail
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                iconText: "󰁍"
                                tooltipText: "Back"
                                foreground: root.contentForeground
                                fontFamily: root.contentFontFamily
                                onClicked: root.backToList()
                            }

                            Text {
                                id: detailTitle
                                anchors.left: backFromDetail.right
                                anchors.leftMargin: Style.spacing.md
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.detailItem.name || ""
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: root.contentForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                            }
                        }

                        Text {
                            width: parent.width
                            text: (root.detailItem.description && root.detailItem.description !== "")
                                ? root.detailItem.description
                                : "No description."
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            color: (root.detailItem.description && root.detailItem.description !== "")
                                ? root.contentForeground
                                : root.dimForeground
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.body
                        }

                        Text {
                            width: parent.width
                            text: "Right-click to edit"
                            horizontalAlignment: Text.AlignRight
                            color: root.dimForeground
                            opacity: 0.7
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }

                    // ============================================================= BIN
                    Column {
                        visible: root.view === "bin"
                        width: parent.width
                        spacing: Style.spacing.md

                        Item {
                            width: parent.width
                            height: Math.max(binTitle.implicitHeight, backFromBin.implicitHeight)

                            PanelActionButton {
                                id: backFromBin
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                iconText: "󰁍"
                                tooltipText: "Back"
                                foreground: root.contentForeground
                                fontFamily: root.contentFontFamily
                                onClicked: root.backToList()
                            }

                            Text {
                                id: binTitle
                                anchors.left: backFromBin.right
                                anchors.leftMargin: Style.spacing.md
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Done"
                                color: root.contentForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.bin.length + " item" + (root.bin.length === 1 ? "" : "s")
                                color: root.dimForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.caption
                            }
                        }

                        Text {
                            visible: root.bin.length === 0
                            width: parent.width
                            text: "Nothing here. Items you tick off land here, so you can bring them back."
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            topPadding: Style.spacing.md
                            bottomPadding: Style.spacing.md
                            color: root.dimForeground
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.body
                        }

                        Repeater {
                            model: root.bin

                            delegate: Item {
                                id: binRow
                                required property var modelData

                                width: bodyColumn.width
                                height: Math.max(restoreButton.implicitHeight, binName.implicitHeight) + Style.spacing.sm

                                PanelActionButton {
                                    id: restoreButton
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconText: "󰕌"
                                    tooltipText: "Restore"
                                    foreground: root.contentForeground
                                    fontFamily: root.contentFontFamily
                                    onClicked: root.restoreItem(binRow.modelData.id)
                                }

                                Text {
                                    id: binName
                                    anchors.left: restoreButton.right
                                    anchors.leftMargin: Style.spacing.md
                                    anchors.right: forgetButton.left
                                    anchors.rightMargin: Style.spacing.md
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: binRow.modelData.name
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    font.strikeout: true
                                    color: root.dimForeground
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.body
                                }

                                PanelActionButton {
                                    id: forgetButton
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconText: "󰗨"
                                    tooltipText: "Delete for good"
                                    foreground: root.contentForeground
                                    fontFamily: root.contentFontFamily
                                    onClicked: root.deleteItem(binRow.modelData.id)
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: emptyBinButton.implicitHeight

                            Button {
                                id: emptyBinButton
                                anchors.right: parent.right
                                text: "Empty bin"
                                bordered: true
                                foreground: root.contentForeground
                                fontFamily: root.contentFontFamily
                                onClicked: root.emptyBin()
                            }
                        }
                    }
                }
            }
        }
    }
}
