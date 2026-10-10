import QtQuick
import QtTest
import qs.services
import qs.tabs.system

// The Home CPU ring shows a dash until CpuLoad has two samples, never a false 0%.
Item {
    width: 400
    height: 120

    SystemRings { id: rings; anchors.fill: parent }

    TestCase {
        name: "HomeRings"
        when: windowShown

        // Every visible text in the tree below `item`.
        function texts(item, found) {
            for (const child of item.children) {
                if (child.text !== undefined && child.visible) found.push(child.text);
                texts(child, found);
            }
            return found;
        }

        function test_cpu_ring_waits_for_a_measured_load() {
            CpuLoad.ready = false;
            CpuLoad.percent = 0;
            verify(!texts(rings, []).includes("0%"), texts(rings, []).join("|"));
            verify(texts(rings, []).includes("-"), texts(rings, []).join("|"));
            CpuLoad.percent = 37.4;
            CpuLoad.ready = true;
            verify(texts(rings, []).includes("37%"), texts(rings, []).join("|"));
        }
    }
}
