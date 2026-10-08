import QtQuick
import QtTest
import qs.picker

// Both picker carousels build on CardCarousel, so one focus rule serves both tabs.
TestCase {
    name: "CardCarousel"
    width: 100
    height: 100
    visible: true
    when: windowShown

    Component {
        id: carouselType
        CardCarousel { count: 4; cardWidth: 100; cardGap: 10; trackHeight: 50; width: 864; height: 50 }
    }

    function test_one_key_moves_one_card_and_stops_at_both_ends() {
        const carousel = createTemporaryObject(carouselType, this);
        carousel.moveFocus(-1);
        compare(carousel.focusIndex, 0);
        carousel.moveFocus(1);
        compare(carousel.focusIndex, 1);
        carousel.moveFocus(-1);
        compare(carousel.focusIndex, 0);
        for (let i = 0; i < 10; i++) carousel.moveFocus(1);
        compare(carousel.focusIndex, 3);
    }

    function test_empty_carousel_keeps_focus_at_zero() {
        const carousel = createTemporaryObject(carouselType, this, { count: 0 });
        carousel.moveFocus(1);
        compare(carousel.focusIndex, 0);
    }

    function test_both_carousels_share_one_viewport_width() {
        compare(createTemporaryObject(carouselType, this).viewportWidth, 864);
    }
}
