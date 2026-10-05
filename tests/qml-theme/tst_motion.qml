import QtQuick
import QtTest
import qs.common
import qs.services

// Each shared motion component moves a value exactly like a plain animation with the same curve.
TestCase {
    id: tests
    name: "SharedMotion"
    width: 100
    height: 100
    visible: true
    when: windowShown

    Item { id: oldA; property real v: 0 }
    Item { id: newA; property real v: 0 }
    Item { id: oldB; property color c: "#000000" }
    Item { id: newB; property color c: "#000000" }

    NumberAnimation { id: plain; target: oldA; property: "v"; from: 0; to: 100; duration: 400; easing.type: Easing.BezierSpline }
    StandardMotion { id: standard; target: newA; property: "v"; from: 0; to: 100; duration: 400 }
    SpringMotion { id: spring; target: newA; property: "v"; from: 0; to: 100; duration: 400 }
    EmphasizedMotion { id: emphasized; target: newA; property: "v"; from: 0; to: 100; duration: 400 }
    ColorAnimation { id: plainColor; target: oldB; property: "c"; from: "#000000"; to: "#ffffff"; duration: 400; easing.type: Easing.BezierSpline }
    StandardColorMotion { id: standardColor; target: newB; property: "c"; from: "#000000"; to: "#ffffff"; duration: 400 }

    function sampleBoth(oldAnim, newAnim, curve) {
        oldAnim.easing.bezierCurve = curve;
        var maxGap = 0, samples = 0, seenMiddle = false;
        oldAnim.start();
        newAnim.start();
        for (var i = 0; i < 30; i++) {
            wait(16);
            var gap = Math.abs(oldA.v - newA.v);
            if (gap > maxGap) maxGap = gap;
            if (oldA.v > 5 && oldA.v < 95) seenMiddle = true;
            samples++;
        }
        tryVerify(function() { return !oldAnim.running && !newAnim.running; }, 2000);
        verify(seenMiddle, "the animation was sampled while it ran");
        // Two animations start in the same frame, so a gap is at most one frame step.
        verify(maxGap < 8, "gap " + maxGap);
        compare(newA.v, 100);
    }

    function test_standard() { sampleBoth(plain, standard, [0.4, 0, 0.2, 1, 1, 1]); }
    function test_spring() { sampleBoth(plain, spring, [0.32, 0.72, 0, 1, 1, 1]); }
    function test_emphasized() { sampleBoth(plain, emphasized, [0.2, 0, 0, 1, 1, 1]); }

    function test_curves_are_the_theme_curves() {
        compare(standard.easing.type, Easing.BezierSpline);
        compare(JSON.stringify(standard.easing.bezierCurve), JSON.stringify([0.4, 0, 0.2, 1, 1, 1]));
        compare(JSON.stringify(spring.easing.bezierCurve), JSON.stringify([0.32, 0.72, 0, 1, 1, 1]));
        compare(JSON.stringify(emphasized.easing.bezierCurve), JSON.stringify([0.2, 0, 0, 1, 1, 1]));
        compare(JSON.stringify(standardColor.easing.bezierCurve), JSON.stringify([0.4, 0, 0.2, 1, 1, 1]));
    }

    function test_color_motion() {
        plainColor.easing.bezierCurve = [0.4, 0, 0.2, 1, 1, 1];
        plainColor.start();
        standardColor.start();
        wait(200);
        compare(newB.c.r.toFixed(2), oldB.c.r.toFixed(2));
        tryVerify(function() { return !standardColor.running && !plainColor.running; }, 2000);
        compare(newB.c.toString(), "#ffffff");
    }
}
