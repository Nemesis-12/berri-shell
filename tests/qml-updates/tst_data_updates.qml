import QtQuick
import QtTest
import qs.services
import qs.tabs.calendar
import qs.tabs.weather
import "../logic/CalendarFormat.js" as Format
import "../logic/CalendarItems.js" as Items

// The real services and views must update bindings after their data changes.
TestCase {
    id: tests
    name: "DataUpdates"
    width: 900
    height: 600
    visible: true
    when: windowShown

    readonly property var selectedItem: Calendar.getItem(Items.itemKey("berri", "one"))
    Component { id: dayPanel; CalendarDayPanel { width: 300; height: 400; selectedDate: new Date(2026, 9, 5) } }
    Component { id: card; WeatherCard { width: 300; height: 272; day: 1 } }
    Component { id: readouts; WeatherReadouts { width: 200; height: 400; day: 1 } }
    Component { id: hourStrip; WeatherHours { width: 600; height: 140; day: 1 } }

    function test_calendar_day_and_selected_details_follow_saved_changes() {
        const document = Format.emptyCalendar();
        document.items = [Items.makeItem({ uid: "one", title: "Before", date: "2026-10-05" })];
        Calendar._calendars = {
            berri: { id: "berri", name: "berri", kind: "local", color: "accent", hidden: false,
                path: Calendar.defaultPath, file: "berri.ics", document: document, text: Format.writeCalendar(document) }
        };
        Calendar._order = ["berri"];
        Calendar._rebuild();
        const panel = createTemporaryObject(dayPanel, tests);
        compare(panel.items[0].title, "Before");
        compare(selectedItem.title, "Before");
        verify(Calendar.update(Items.itemKey("berri", "one"), { title: "After" }));
        compare(panel.items[0].title, "After");
        compare(selectedItem.title, "After");
    }

    function test_weather_cards_readouts_and_hours_follow_a_forecast_change() {
        Weather.model = {
            current: { tempC: 24, code: 3, isDay: true, minC: 17, maxC: 26, feelsLikeC: 25,
                humidity: 60, dewPointC: 15, windKmh: 12, windDirection: "N", gustKmh: 15,
                precipMm: 1, precipProbability: 20, uvIndex: 3, uvLabel: "Moderate", pressureHpa: 1000,
                sunrise: "07:00", sunset: "19:00", daylight: "12h" },
            days: [{ date: new Date(2026, 9, 5) },
                { date: new Date(2026, 9, 6), code: 3, minC: 17, maxC: 26, feelsLikeMax: 25,
                    humidityMean: 60, dewPointMean: 15, windMaxKmh: 12, windDirection: "N", gustMaxKmh: 15,
                    precipMm: 1, precipProbability: 20, uvMax: 3, pressureHpa: 1000,
                    sunrise: "07:00", sunset: "19:00", daylight: "12h" }],
            hoursAll: [{ time: new Date(2026, 9, 6, 9), tempC: 24, code: 3, isDay: true, precipProbability: 20 }],
            nowIndex: 0
        };
        Weather.updatedAt = 1;
        const weatherCard = createTemporaryObject(card, tests);
        const weatherReadouts = createTemporaryObject(readouts, tests);
        const weatherHours = createTemporaryObject(hourStrip, tests);
        compare(weatherCard.detail.tempC, 26);
        compare(weatherReadouts.cells[0].value, "60");
        compare(weatherHours.hours[0].tempC, 24);
        // Nested JS fields do not emit QML property changes. The update time must notify callers.
        Weather.model.days[1].maxC = 31;
        Weather.model.days[1].humidityMean = 70;
        Weather.model.hoursAll[0].tempC = 29;
        Weather.updatedAt = 2;
        compare(weatherCard.detail.tempC, 31);
        compare(weatherReadouts.cells[0].value, "70");
        compare(weatherHours.hours[0].tempC, 29);
        Weather.model = Object.assign({}, Weather.model, { days: [Weather.model.days[0],
            Object.assign({}, Weather.model.days[1], { maxC: 33, humidityMean: 75 })] });
        compare(weatherCard.detail.tempC, 33);
        compare(weatherReadouts.cells[0].value, "75");
    }
}
