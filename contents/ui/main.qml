import QtQuick 6.5
import QtQuick.Controls 6.5 as Controls
import QtQuick.Layouts 6.5
import Qt5Compat.GraphicalEffects
import org.kde.plasma.core 6 as PlasmaCore
import org.kde.plasma.components 6 as PlasmaComponents
import org.kde.plasma.plasmoid 2.0
import org.kde.i18n 1.0

Item {
    id: root
    width: 420
    height: collapsed ? headerBar.implicitHeight + padding * 2 : 320
    property bool collapsed: false
    property bool commandRunning: false
    property real padding: 12
    property alias commandText: commandField.text
    property var commandHistory: []
    property string lastShell: ""
    property string scriptPath: plasmoid.file("scripts", "shell_runner.py")
    property real windowOpacity: 0.9
    property bool optionsVisible: false
    property bool isDark: relativeLuminance(theme.backgroundColor) < 0.4

    readonly property PlasmaCore.Theme theme: PlasmaCore.Theme {
        id: theme
        colorGroup: PlasmaCore.Theme.View
    }

    Plasmoid.switchWidth: 420
    Plasmoid.switchHeight: 320
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation

    QtObject {
        id: colorPalette
        property color background: PlasmaCore.Theme.backgroundColor
        property color header: isDark ? Qt.tint(background, Qt.rgba(1, 1, 1, 0.04)) : Qt.darker(background, 1.02)
        property color terminalBackground: isDark ? Qt.darker(background, 1.3) : Qt.lighter(background, 1.1)
        property color border: PlasmaCore.Theme.disabledTextColor
        property color text: PlasmaCore.Theme.textColor
        property color accent: PlasmaCore.Theme.highlightColor
    }

    DropShadow {
        anchors.fill: container
        horizontalOffset: 0
        verticalOffset: 6
        radius: 18
        samples: 24
        color: Qt.rgba(0, 0, 0, 0.35)
        source: container
        transparentForMouseEvents: true
    }

    Rectangle {
        id: container
        anchors.fill: parent
        anchors.margins: 0
        radius: 14
        color: colorPalette.background
        border.color: Qt.rgba(colorPalette.border.r, colorPalette.border.g, colorPalette.border.b, 0.5)
        border.width: 1
        opacity: windowOpacity
        antialiasing: true
        layer.enabled: true
        layer.smooth: true

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.InOutQuad
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: padding
            spacing: 10

            Rectangle {
                id: headerBar
                Layout.fillWidth: true
                height: 38
                radius: container.radius - 4
                color: colorPalette.header
                border.color: Qt.rgba(colorPalette.border.r, colorPalette.border.g, colorPalette.border.b, 0.4)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Controls.Label {
                        id: titleLabel
                        text: i18n("Terminal Buddy")
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        color: colorPalette.text
                        elide: Text.ElideRight
                    }

                    Controls.ToolButton {
                        text: "⚙️"
                        focusPolicy: Qt.NoFocus
                        onClicked: plasmoid.openConfiguration()
                        ToolTip.text: i18n("Settings")
                    }

                    Controls.ToolButton {
                        text: collapsed ? "◻" : "–"
                        focusPolicy: Qt.NoFocus
                        onClicked: collapsed = !collapsed
                        ToolTip.text: collapsed ? i18n("Restore") : i18n("Collapse")
                    }

                    Controls.ToolButton {
                        text: "✖"
                        focusPolicy: Qt.NoFocus
                        onClicked: plasmoid.remove()
                        ToolTip.text: i18n("Close")
                    }
                }

                DragHandler {
                    id: dragHandler
                    target: root
                    grabPermissions: PointerHandler.CanTakeOverFromAnything
                    cursorShape: Qt.OpenHandCursor
                }
            }

            ColumnLayout {
                id: terminalBody
                Layout.fillWidth: true
                Layout.fillHeight: !collapsed
                Layout.preferredHeight: collapsed ? 0 : -1
                spacing: 10
                visible: !collapsed
                opacity: collapsed ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.InOutQuad
                    }
                }

                Controls.TextArea {
                    id: outputArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readOnly: true
                    wrapMode: TextEdit.WrapAnywhere
                    textFormat: TextEdit.PlainText
                    background: Rectangle {
                        color: colorPalette.terminalBackground
                        radius: 10
                        border.width: 0
                    }
                    selectByKeyboard: true
                    selectByMouse: true
                    padding: 10
                    font.family: theme.monoFont.family.length > 0 ? theme.monoFont.family : "JetBrains Mono"
                    font.pointSize: theme.monoFont.pointSize > 0 ? theme.monoFont.pointSize : 10
                    color: colorPalette.text
                    placeholderText: i18n("Command output will appear here…")
                    ScrollBar.vertical.policy: Controls.ScrollBar.AsNeeded
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Controls.TextField {
                        id: commandField
                        Layout.fillWidth: true
                        placeholderText: i18n("Enter command…")
                        enabled: !commandRunning
                        onAccepted: runCommand()
                        font.family: outputArea.font.family
                    }

                    Controls.Button {
                        id: runButton
                        text: commandRunning ? i18n("Running…") : i18n("Run")
                        enabled: !commandRunning
                        onClicked: runCommand()
                    }

                    Controls.ToolButton {
                        id: optionsButton
                        text: optionsVisible ? "▾" : "▸"
                        ToolTip.text: optionsVisible ? i18n("Hide options") : i18n("Show options")
                        onClicked: optionsVisible = !optionsVisible
                    }
                }

                Item {
                    id: optionsPanel
                    Layout.fillWidth: true
                    Layout.preferredHeight: optionsVisible ? optionsContent.implicitHeight : 0
                    clip: true

                    ColumnLayout {
                        id: optionsContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 0
                        spacing: 6
                        opacity: optionsVisible ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 140
                                easing.type: Easing.InOutQuad
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Controls.Label {
                                text: i18n("Opacity")
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Controls.Slider {
                                id: opacitySlider
                                Layout.fillWidth: true
                                from: 0.4
                                to: 1.0
                                stepSize: 0.05
                                value: root.windowOpacity
                                onValueChanged: root.windowOpacity = value
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Controls.Label {
                                text: i18n("Shell")
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Controls.Label {
                                text: lastShell.length > 0 ? lastShell : i18n("Auto")
                                font.italic: lastShell.length === 0
                                Layout.fillWidth: true
                            }
                            Controls.Button {
                                text: i18n("Clear")
                                onClicked: {
                                    outputArea.text = ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    PlasmaComponents.ResizeHandle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 4
        visible: !collapsed
        target: root
    }

    Shortcut {
        sequences: ["Ctrl+Enter", "Meta+Return"]
        context: Qt.ApplicationShortcut
        onActivated: runCommand()
    }

    Shortcut {
        sequences: ["Ctrl+L"]
        context: Qt.ApplicationShortcut
        onActivated: clearOutput()
    }

    PlasmaCore.DataSource {
        id: shellRunner
        engine: "executable"

        onNewData: function (source, data) {
            if (data["stdout"] && data["stdout"].length > 0) {
                try {
                    const payload = JSON.parse(data["stdout"])
                    handleResponse(payload)
                } catch (e) {
                    appendOutput(data["stdout"])
                }
            }

            if (data["stderr"] && data["stderr"].length > 0) {
                appendOutput(data["stderr"])
            }

            shellRunner.disconnectSource(source)
        }

        onSourceDisconnected: {
            commandRunning = false
        }
    }

    function shellQuote(text) {
        if (text === undefined || text === null) {
            return "''"
        }
        return "'" + String(text).split("'").join("'\\''") + "'"
    }

    function relativeLuminance(color) {
        if (!color) {
            return 0
        }
        function adjust(channel) {
            return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * adjust(color.r) + 0.7152 * adjust(color.g) + 0.0722 * adjust(color.b)
    }

    function clearOutput() {
        outputArea.text = ""
    }

    function runCommand() {
        const command = commandField.text.trim()
        if (!command || commandRunning) {
            return
        }

        commandRunning = true
        appendOutput("> " + command)

        const encoded = Qt.btoa(command)
        const runnerSource = "python3 " + shellQuote(scriptPath) + " --run --encoded " + shellQuote(encoded)
        shellRunner.connectSource(runnerSource)
        commandField.text = ""
    }

    function handleResponse(message) {
        if (!message || typeof message !== "object") {
            return
        }

        if (message.type === "run") {
            lastShell = message.shell || ""
            if (message.stdout && message.stdout.length > 0) {
                appendOutput(message.stdout)
            }
            if (message.stderr && message.stderr.length > 0) {
                appendOutput(message.stderr)
            }

            if (message.action === "clear") {
                clearOutput()
            } else if (message.action === "exit") {
                plasmoid.remove()
            }

            commandHistory = message.history || []
        } else if (message.type === "history") {
            commandHistory = message.history || []
            if (message.last_command) {
                commandField.text = message.last_command
            }
            if (message.shell) {
                lastShell = message.shell
            }
        }
    }

    function appendOutput(text) {
        if (!text || text.length === 0) {
            return
        }
        const existing = outputArea.text
        if (existing.length > 0 && !existing.endsWith("\n")) {
            outputArea.text += "\n"
        }
        outputArea.text += text
        outputArea.cursorPosition = outputArea.text.length
    }

    Component.onCompleted: {
        const historySource = "python3 " + shellQuote(scriptPath) + " --history"
        shellRunner.connectSource(historySource)
    }
}
