import QtQuick
import QtTest
import qs.services
import qs.pill

TestCase {
    id: tests
    name: "ThemeSwitch"

    SignalSpy { id: spy; target: Theme; signalName: "wallpaperTransition" }

    function init() {
        Theme.palettes = [
            { key: "one", name: "One", c: { accent: "#c28bf2", background: "#36295c", lighter_background: "#3b2c62", bright_foreground: "#f3ecf7" } },
            { key: "two", name: "Two", c: {} }
        ];
        spy.clear();
    }

    // The same options start one wallpaper transition at every duration around 450 ms.
    function test_one_wallpaper_transition_per_switch_data() {
        return [{ ms: 449 }, { ms: 450 }, { ms: 451 }];
    }
    function test_one_wallpaper_transition_per_switch(data) {
        Theme.apply("one", { animate: true, persist: false, wallpaper: true, durationMs: data.ms });
        compare(spy.count, 1);
        compare(spy.signalArguments[0][1], data.ms);
        Theme.apply("two", { animate: true, persist: false, wallpaper: true, durationMs: data.ms });
        compare(spy.count, 2);
    }

    function test_no_wallpaper_transition_without_the_option_data() {
        return [{ ms: 449 }, { ms: 450 }, { ms: 451 }, { ms: 700 }];
    }
    function test_no_wallpaper_transition_without_the_option(data) {
        Theme.apply("one", { animate: true, persist: false, durationMs: data.ms });
        compare(spy.count, 0);
    }

    function test_a_silent_apply_makes_no_transition() {
        Theme.apply("one", { animate: false, persist: false, wallpaper: true });
        compare(spy.count, 0);
        compare(Theme.currentKey, "one");
    }

    function test_an_empty_palette_gives_every_token() {
        Theme.apply("two", { animate: false, persist: false });
        compare(Theme.accent.toString(), "#c28bf2");
        compare(Object.keys(Theme.toRaw).length, 9);
        verify(Theme.border.a === 1);
    }

    function test_tray_hover_fill_equals_button_hover_fill() {
        Theme.apply("one", { animate: false, persist: false });
        compare(PillTrayStyle.hoverFill.toString(), Theme.hover.toString());
        compare(PillTrayStyle.hoverFillClear.a, 0);
        compare(PillTrayStyle.hoverFillClear.r, Theme.hover.r);
    }

    // The blend ends on the target colors of the palette.
    function test_the_blend_ends_on_the_target_colors() {
        Theme.apply("two", { animate: false, persist: false });
        Theme.apply("one", { persist: false, durationMs: 60 });
        wait(300);
        compare(Theme.accent.toString(), "#c28bf2");
        compare(Theme.raised.toString(), "#3b2c62");
        compare(Theme.card.toString(), "#36295c");
        compare(Theme.hover.toString(), "#483a6e");
    }
}
