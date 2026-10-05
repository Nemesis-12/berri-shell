import QtQuick

/**
 * What a tab asks of the panel that shows it (the pill dashboard). A tab body
 * owns one PanelRequests and offers it as a `requests` property. The panel
 * reads only the active tab's requests, so the panel holds no state of any
 * single tab.
 */
QtObject {
    /** The tab needs real keyboard focus now (a text field or the Wi-Fi password row). */
    property bool wantsKeyboard: false

    /**
     * The tab wants a dialog (a normal window). The panel closes first, so the dialog
     * is not hidden under it. `openDialog` is a function. `afterClose` true: it runs
     * when the panel is at rest. False: it runs as the close starts.
     */
    signal dialogRequested(var openDialog, bool afterClose)

    /** The tab wants the panel open on this tab again (after a dialog). */
    signal reopenRequested()
}
