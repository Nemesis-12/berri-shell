import QtQuick
import Quickshell
import "../logic/CalendarCatalog.js" as Catalog
import "../logic/CalendarItems.js" as Items
import "../logic/CalendarQueries.js" as Queries

/**
 * The subscribed links of Calendar.qml: checks, adds and refreshes feeds, and
 * downloads every link again each 30 minutes. Calendar supplies request data
 * and accepts results through named operations on `store`; `files` supplies
 * download and file access. Stored entries and view updates stay with Calendar.
 */
QtObject {
    id: links

    required property QtObject store
    required property CalendarFiles files

    readonly property string badLinkText: "Use an https:// or webcal:// link"

    /** Starts a link check and reports invalid input on the next event turn. */
    function check(url: string): void {
        var https = Queries.feedUrl(url);
        if (!https) { Qt.callLater(function () { store.linkChecked(url, false, "", 0, badLinkText, 0); }); return; }
        download("check", url, https, "");
    }

    /** Starts a subscription and carries its request id through every result. */
    function subscribe(url: string, color): int {
        var requestId = store.nextSubscriptionRequest();
        var https = Queries.feedUrl(url);
        if (!https) {
            Qt.callLater(function () { store.subscribed(url, "", badLinkText, requestId); });
            return requestId;
        }
        var id = "l-" + Items.shortHash(https);
        if (store.hasCalendar(id)) {
            Qt.callLater(function () { store.subscribed(url, id, "", requestId); });
            return requestId;
        }
        download("subscribe", url, https, id, color, requestId);
        return requestId;
    }

    /** Downloads an existing link when Calendar accepts its refresh request. */
    function refresh(id: string): void {
        var request = store.beginLinkRefresh(id, badLinkText);
        if (!request) return;
        download("refresh", request.shownUrl, request.url, request.calendarId);
    }

    // Every link is downloaded again each 30 minutes, and once at start when its cache is older.
    function refreshAll(onlyStale: bool): void {
        var ids = store.linkRefreshIds(onlyStale);
        for (var i = 0; i < ids.length; i++) refresh(ids[i]);
    }

    readonly property Timer refreshTimer: Timer {
        interval: 30 * 60000
        repeat: true
        running: links.store.ready
        onTriggered: links.refreshAll(false)
    }

    /** Sends a download request through the injected file access. */
    function download(purpose: string, shownUrl: string, url: string, id: string, color, requestId): void {
        files.download({ purpose: purpose, shownUrl: shownUrl, url: url, calendarId: id,
            color: color === undefined || color === null ? "" : String(color), requestId: requestId || 0 });
    }

    // Removes the files of a link check that is not kept.
    function removeCheckFiles(jsonPath: string): void {
        Quickshell.execDetached(["sh", "-c",
            'rm -f "$1" "$2"; rmdir "$3"', "sh", jsonPath,
            jsonPath.replace(/feed\.json$/, "feed.ics"), jsonPath.slice(0, jsonPath.lastIndexOf("/"))]);
    }

    // A check reports what is in the feed. Nothing is saved.
    function finishCheck(shownUrl: string, name: string, doc: var, error: string): void {
        var records = doc ? doc.records : [];
        store.linkChecked(shownUrl, !error, name, records.length, error,
            doc ? store.countLinkDuplicates(records) : 0);
    }

    // Handles a finished download: the error, the records and what the request wanted.
    function downloaded(request: var, code: int, jsonPath: string): void {
        var error = Catalog.downloadError(code, { parserMissing: files.exitParserMissing, notCalendar: files.exitNotCalendar,
            saveFailed: files.exitSaveFailed }, { parserMissing: store.parserMissingText });
        var doc = null;
        var json = "";
        if (!error) {
            json = files.readNow(jsonPath) || "";
            doc = Catalog.parseRecords(json);
            if (!doc) error = store.recordsErrorText;
        }
        if (request.purpose === "check" && jsonPath) removeCheckFiles(jsonPath);
        if (error) {
            console.error("Calendar: " + error);
            if (code === files.exitParserMissing) store.setParserError(error);
        } else store.setParserError("");
        var name = doc ? doc.name || Queries.linkHost(request.url) : "";
        if (request.purpose === "check") finishCheck(request.shownUrl, name, doc, error);
        else if (request.purpose === "subscribe") store.acceptSubscription(request, name, doc, json, error);
        else store.acceptLinkRefresh(request.calendarId, doc, json, error);
    }
}
