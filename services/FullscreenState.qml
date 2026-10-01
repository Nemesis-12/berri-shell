pragma Singleton
import Quickshell
import Quickshell.Hyprland

/**
 * Tells if a monitor shows a window in fullscreen or maximized mode.
 * Hyprland reports `fullscreen` 1 for maximize (this is what Super+Alt+F
 * sets) and 2 for real fullscreen. Tiled fullscreen (Super+Ctrl+F) reports 0
 * and does not count. Only the ACTIVE workspace of the monitor is checked.
 * Call it inside a property binding: it re-runs when Hyprland data changes.
 */
Singleton {
    /**
     * The highest fullscreen mode of a window on the active workspace of the
     * monitor: 0 none, 1 maximized, 2 real fullscreen. Call it inside a binding.
     */
    function modeOn(screen: var): int {
        var monitor = Hyprland.monitorFor(screen);
        var workspace = monitor ? monitor.activeWorkspace : null;
        var activeId = workspace ? workspace.id : -1;
        if (activeId === -1) return 0;
        var windows = Hyprland.toplevels.values;
        var mode = 0;
        for (var i = 0; i < windows.length; i++) {
            var info = windows[i] ? windows[i].lastIpcObject : null;
            if (info && info.workspace && info.workspace.id === activeId && info.fullscreen > mode)
                mode = info.fullscreen;
        }
        return mode;
    }

    function coversMonitor(screen: var): bool {
        var monitor = Hyprland.monitorFor(screen);
        var workspace = monitor ? monitor.activeWorkspace : null;
        var activeId = workspace ? workspace.id : -1;
        if (activeId === -1) return false;
        var windows = Hyprland.toplevels.values;
        for (var i = 0; i < windows.length; i++) {
            var info = windows[i] ? windows[i].lastIpcObject : null;
            if (info && info.fullscreen >= 1 && info.workspace && info.workspace.id === activeId)
                return true;
        }
        return false;
    }
}
