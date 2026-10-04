.pragma library

// Calendar.qml uses Qt and the system zone database to read an IANA zone clock.
function instant(value, zone) {
    return Date.fromLocaleString(Qt.locale("C"), value + " " + zone, "yyyyMMdd'T'HHmmss tttt").getTime();
}
