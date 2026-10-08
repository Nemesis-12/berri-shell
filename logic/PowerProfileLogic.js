.pragma library

// Rules for the "auto" power mode. Profiles are plain names; the service maps them to PowerProfile values.

// Keeps the samples inside the window, with the new sample last.
function recentSamples(samples, sample, windowMs) {
    return samples.concat([sample]).filter(function (item) { return sample.time - item.time <= windowMs; });
}

// Mean load of the samples.
function averageLoad(samples) {
    var total = samples.reduce(function (sum, sample) { return sum + sample.load; }, 0);
    return total / samples.length;
}

// Debounces one threshold test. A new raw side restarts the sustain window;
// the state follows the raw side only after it held for sustainMs.
function sustainedSide(previous, raw, now, sustainMs) {
    var next = { side: previous.side, since: previous.since, debounced: previous.debounced };
    if (raw !== previous.side) {
        next.side = raw;
        next.since = now;
    }
    if (now - next.since >= sustainMs) next.debounced = raw;
    return next;
}

// High load wins; low load saves power only on battery.
function recommendedProfile(highDebounced, lowDebounced, onBattery) {
    if (highDebounced) return "performance";
    if (onBattery && lowDebounced) return "power-saver";
    return "balanced";
}

// A switch needs a new profile and a finished cooldown since the last switch.
function mayAdopt(recommended, applied, now, lastSwitchTime, cooldownMs) {
    return recommended !== applied && now - lastSwitchTime >= cooldownMs;
}
