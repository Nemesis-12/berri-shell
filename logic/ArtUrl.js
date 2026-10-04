.pragma library

/** Album art may load only from a local file or an HTTPS link. Anything else gives "". */
function safeArtUrl(url) {
    var text = String(url || "");
    return /^(file:\/\/|https:\/\/)/i.test(text) ? text : "";
}
