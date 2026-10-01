// Pure decision logic for airplane mode, mirroring the mock's toggle('air')
// and the wifi/bt-on branch of toggle('wifi'|'bt'). Kept free of any
// Quickshell/QML API so it can be called and tested on its own.
.pragma library

/**
 * state: { air: bool, memoValid: bool, memoWifi: bool, memoBt: bool,
 *          wifi: bool, bt: bool }
 * action: "toggleAir" (flip airplane) | "radioOn" (a radio just turned on)
 *
 * Returns a partial state object with only the fields that change; fields
 * left out mean "no change".
 */
function nextState(state, action) {
    if (action === "toggleAir") {
        if (state.air) {
            // Turning airplane off: restore the radios it remembered, or
            // default both to on if nothing was remembered (e.g. after a
            // shell restart that lost the memo).
            return {
                air: false,
                memoValid: false,
                memoWifi: false,
                memoBt: false,
                wifi: state.memoValid ? state.memoWifi : true,
                bt: state.memoValid ? state.memoBt : true
            };
        }
        // Turning airplane on: remember the current radios, then turn both off.
        return {
            air: true,
            memoValid: true,
            memoWifi: state.wifi,
            memoBt: state.bt,
            wifi: false,
            bt: false
        };
    }
    if (action === "radioOn") {
        // A radio just turned on (tile, list switch, or outside the shell).
        // Clear airplane if it was set; otherwise nothing changes.
        if (!state.air) return {};
        return { air: false, memoValid: false, memoWifi: false, memoBt: false };
    }
    return {};
}
