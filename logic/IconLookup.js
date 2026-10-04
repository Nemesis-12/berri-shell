.pragma library

// Names that already produced a warning. A pragma library is shared by every
// Icon, so each unknown name warns once for the whole shell.
var warned = Object.create(null);

// Returns the SVG path for a Lucide icon name. An empty name means "no icon"
// and gives "". An unknown name gives "" and one warning.
function pathFor(paths, name) {
    if (name === "") return "";
    if (Object.prototype.hasOwnProperty.call(paths, name)) return paths[name];
    if (!warned[name]) {
        warned[name] = true;
        console.warn("Icon: unknown Lucide icon name '" + name + "'. Add its SVG to assets/icons/lucide/ and run tools/lucide-to-qml.py.");
    }
    return "";
}
