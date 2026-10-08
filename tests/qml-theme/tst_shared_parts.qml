import QtQuick
import QtTest
import qs.common

// Shared parts keep one rule for every place that uses them.
TestCase {
    id: tests
    name: "SharedParts"
    width: 400
    height: 400
    visible: true
    when: windowShown

    function cellsOf(row) {
        return row.children[0].children.filter(item => item.chosen !== undefined);
    }

    function test_segment_row_cells_are_equal_for_any_option_count() {
        for (const count of [2, 3, 4]) {
            const options = [];
            for (let i = 0; i < count; i++) options.push({ key: "k" + i, label: "L" + i });
            const row = createTemporaryObject(segmentType, tests, { options: options, current: "k0" });
            const cells = cellsOf(row);
            compare(cells.length, count);
            for (const cell of cells) fuzzyCompare(cell.width, cells[0].width, 0.001);
            // Cells and the 1px lines between them fill the row exactly.
            fuzzyCompare(cells.length * cells[0].width + (count - 1) + 2, row.width, 0.001);
        }
    }

    Component { id: segmentType; SegmentRow { width: 300 } }

    function test_toggle_switch_slides_the_knob_and_reports_clicks() {
        const toggle = createTemporaryObject(toggleType, tests);
        const knob = toggle.children[0];
        compare(knob.x, 2);
        toggle.checked = true;
        // The knob is on its way, not yet at the end, and arrives there.
        verify(knob.x < 18, "The knob must not jump");
        tryCompare(knob, "x", 18);
        let clicks = 0;
        toggle.toggled.connect(() => clicks++);
        mouseClick(toggle);
        compare(clicks, 1);
    }

    function test_toggle_switch_created_on_has_the_knob_in_place() {
        const toggle = createTemporaryObject(toggleType, tests, { checked: true });
        compare(toggle.children[0].x, 18);
        wait(50);
        compare(toggle.children[0].x, 18);
    }

    Component { id: toggleType; ToggleSwitch {} }

    function test_fill_clip_keeps_content_in_place() {
        const meter = createTemporaryObject(meterType, tests);
        const clip = meter.children[0];
        compare(clip.height, 30);
        compare(clip.y, 70);
        const inner = clip.children[0].children[0];
        compare(clip.mapFromItem(meter, 0, 0).y + 0, -70);
        compare(inner.mapToItem(meter, 0, 0).y, 0);
    }

    Component {
        id: meterType
        Item {
            width: 50; height: 100
            FillClip { fillHeight: 30; Rectangle { width: 10; height: 10 } }
        }
    }
}
