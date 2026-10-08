import QtQuick
import Quickshell
import "../logic/CalendarCatalog.js" as Catalog
import "../logic/CalendarItems.js" as Items
import "../logic/CalendarQueries.js" as Queries

/**
 * The subscribed links of Calendar.qml: checks, adds and refreshes feeds, and
 * downloads every link again each 30 minutes. `store` is the Calendar singleton
 * that owns the calendars and the signals; this part only reads and changes them.
 */
QtObject {
    id: links

    required property var store

    readonly property string badLinkText: "Use an https:// or webcal:// link"

    function check(url: string): void {
        var https = Queries.feedUrl(url);
        if (!https) { Qt.callLater(function () { store.linkChecked(url, false, "", 0, badLinkText, 0); }); return; }
        download("check", url, https, "");
    }

    function subscribe(url: string, color): int {
        var requestId = ++store._nextSubscription;
        var https = Queries.feedUrl(url);
        if (!https) {
            Qt.callLater(function () { store.subscribed(url, "", badLinkText, requestId); });
            return requestId;
        }
        var id = "l-" + Items.shortHash(https);
        if (store._calendars[id]) {
            Qt.callLater(function () { store.subscribed(url, id, "", requestId); });
            return requestId;
        }
        download("subscribe", url, https, id, color, requestId);
        return requestId;
    }

    function refresh(id: string): void {
        var meta = store._calendars[id];
        if (!meta || meta.kind !== "link" || meta.refreshing) return;
        // A saved link is checked like a typed one: no download for a rejected link.
        var https = Queries.feedUrl(meta.url);
        if (!https) { meta.error = badLinkText; return; }
        meta.refreshing = true;
        download("refresh", meta.url, https, id);
    }

    // Every link is downloaded again each 30 minutes, and once at start when its cache is older.
    function refreshAll(onlyStale: bool): void {
        var limit = Date.now() - 30 * 60000;
        for (var i = 0; i < store._order.length; i++) {
            var meta = store._calendars[store._order[i]];
            if (meta.kind === "link" && (!onlyStale || meta.updatedAt < limit)) refresh(meta.id);
        }
    }

    readonly property Timer refreshTimer: Timer {
        interval: 30 * 60000
        repeat: true
        running: store.ready
        onTriggered: links.refreshAll(false)
    }

    function download(purpose: string, shownUrl: string, url: string, id: string, color, requestId): void {
        store._files.download({ purpose: purpose, shownUrl: shownUrl, url: url, calendarId: id,
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
        var calendars = store._order.map(function (key) { return store._calendars[key]; });
        store.linkChecked(shownUrl, !error, name, records.length, error,
            doc ? Queries.countStoredDuplicates(records, calendars) : 0);
    }

    // A new link becomes a calendar with its records.
    function finishSubscribe(request: var, name: string, doc: var, json: string, error: string): void {
        var id = request.calendarId;
        if (error) { store.subscribed(request.shownUrl, "", error, request.requestId); return; }
        if (store._calendars[id]) { store.subscribed(request.shownUrl, id, "", request.requestId); return; }
        var calendar = store._addCalendar(id, "link", name, "subscriptions/" + id + ".ics", request.url, request.color);
        calendar.records = doc.records;
        calendar.signature = Catalog.recordsSignature(json);
        calendar.loaded = true;
        store._finishAdd();
        store.subscribed(request.shownUrl, id, "", request.requestId);
    }

    // A refresh keeps the old records on an error. A feed with the same text and no error to clear keeps its cached months.
    function finishRefresh(id: string, doc: var, json: string, error: string): void {
        var meta = store._calendars[id];
        if (!meta) return;
        meta.refreshing = false;
        var result = error ? null : Catalog.refreshResult(meta, doc, json);
        var same = !error && result.same;
        if (error) {
            meta.error = error;
        } else {
            if (!same) meta.records = doc.records;
            meta.signature = result.signature;
            meta.loaded = true;
            meta.error = "";
            meta.convertError = "";
            meta.colorOverrides = result.overrides;
            meta.updatedAt = Date.now();
            store._saveState();
        }
        if (same) store._refreshRow(meta);
        else store._rebuild();
    }

    // Handles a finished download: the error, the records and what the request wanted.
    function downloaded(request: var, code: int, jsonPath: string): void {
        var files = store._files;
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
            if (code === files.exitParserMissing) store.parserError = error;
        } else store.parserError = "";
        var name = doc ? doc.name || Queries.linkHost(request.url) : "";
        if (request.purpose === "check") finishCheck(request.shownUrl, name, doc, error);
        else if (request.purpose === "subscribe") finishSubscribe(request, name, doc, json, error);
        else finishRefresh(request.calendarId, doc, json, error);
    }
}
