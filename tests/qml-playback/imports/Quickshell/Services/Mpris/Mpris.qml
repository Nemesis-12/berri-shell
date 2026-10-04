pragma Singleton
import QtQuick

// Supplies player arrival, removal, and metadata changes to the real service.
QtObject { property ListModel players: ListModel { property var values: [] } }
