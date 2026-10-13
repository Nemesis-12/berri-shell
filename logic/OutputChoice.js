.pragma library

/**
 * The output devices to show in `limit` tiles. Devices keep their order, but
 * the active output (`defaultSink`) always gets a tile: when it is past the
 * limit, it takes the last tile.
 */
function shownOutputs(sinks, defaultSink, limit) {
    var shown = sinks.slice(0, limit);
    if (defaultSink && shown.indexOf(defaultSink) < 0 && sinks.indexOf(defaultSink) >= 0)
        shown[limit - 1] = defaultSink;
    return shown;
}
