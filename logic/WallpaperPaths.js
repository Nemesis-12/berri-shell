.pragma library

/**
 * True when `path` names a file directly inside the wallpaper folder `dir`.
 * Saved library entries are not trusted: a path outside the folder, the
 * folder itself, a "." or ".." name, or a path through a sub-folder (which
 * could be a symbolic link to another place) must never be deleted.
 * The check reads the text only; a link that is itself a direct child is
 * safe because deleting it removes the link, not its target.
 */
function isLibraryFile(dir, path) {
    if (typeof dir !== "string" || typeof path !== "string") return false;
    var root = dir.replace(/\/+$/, "");
    if (root === "" || path.indexOf(root + "/") !== 0) return false;
    var name = path.slice(root.length + 1);
    return name !== "" && name !== "." && name !== ".." && name.indexOf("/") < 0 && name.indexOf("\0") < 0;
}
