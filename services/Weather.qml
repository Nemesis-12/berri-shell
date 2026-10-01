pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/WeatherParse.js" as WeatherParse

/**
 * Weather data for the pill, the Home cell and the Weather tab. Location comes from Omarchy's own weather
 * settings file; if that is missing or invalid, falls back to wttr.in's IP
 * lookup. Actual conditions come from Open-Meteo. Refreshes every 15 min.
 * One Open-Meteo request per refresh gives current values, 7 days and hourly data.
 * On failure the last good data stays and `error` holds a short text.
 * Temperatures are in Celsius; use formatTemp() to honour `unitF`.
 * Times: `sunrise`, `sunset` are local "HH:MM" strings; `hours[].time` and `days[].date` are Dates.
 */
Singleton {
    id: root

    readonly property string locationPath: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/settings/weather.json"

    property real latitude: NaN
    property real longitude: NaN

    /** True once a real reading has been received at least once. */
    property bool ready: false
    property int temperatureC: 0
    property int weatherCode: 3
    property bool isDay: true

    /** Short place name, "City, CC". Empty until known. */
    property string locationName: ""
    /** Time (ms since epoch) of the last good fetch; 0 before the first one. */
    property real updatedAt: 0
    property bool loading: false
    /** "" or a short text about the last failed refresh. */
    property string error: ""

    // Other current readouts (same names as dayDetail(0)).
    property int feelsLikeC: 0
    property int humidity: 0
    property int dewPointC: 0
    property int windKmh: 0
    property string windDirection: ""
    property int gustKmh: 0
    /** Expected precipitation for today, mm. */
    property real precipMm: 0
    property int precipProbability: 0
    property real uvIndex: 0
    property string uvLabel: "Low"
    property int pressureHpa: 0
    property string sunrise: ""
    property string sunset: ""
    property string daylight: ""

    /** Next 24 hours from the current hour: { time, code, isDay, tempC, precipProbability }. */
    property var hours: []
    /** 7 days: { date, code, minC, maxC, precipProbability, precipMm, sunrise, sunset, uvMax,
     *  windMaxKmh, gustMaxKmh, humidityMean, dewPointMean, feelsLikeMax }. */
    property var days: []

    /** Not used yet; the settings page will set it. */
    property bool unitF: false
    function formatTemp(c) {
        return unitF ? Math.round(c * 9 / 5 + 32) + "°" : Math.round(c) + "°";
    }

    // Parsed model from WeatherParse.parse(); backs dayDetail() and hoursFor().
    property var model: null

    /** Readouts for day `index` (0 = now). Same field names as the current properties, plus tempC, minC, maxC, code. */
    function dayDetail(index) {
        return model ? WeatherParse.dayDetail(model, index) : null;
    }

    /** Hours of day `index`; for 0, from the current hour to the end of today. */
    function hoursFor(index) {
        return model ? WeatherParse.hoursFor(model, index) : [];
    }

    /** Fetch now and restart the 15-minute timer. */
    function refresh() {
        refreshTimer.restart();
        if (hasCoords()) fetchWeather(); else resolveLocation();
    }

    /** Lucide icon name for the current WMO code + day/night; shared by the pill and the weather cell. */
    readonly property string iconName: iconForGroup(weatherGroup(weatherCode), isDay)
    /** Condition label ("Cloudy", "Rain", ...) for the current WMO code; shared by the pill and the weather cell. */
    readonly property string conditionLabel: labelForGroup(weatherGroup(weatherCode))

    // Keep the shared weather mappings available to existing views.
    function weatherGroup(code) {
        return WeatherParse.weatherGroup(code);
    }

    function iconForGroup(group, isDay) {
        return WeatherParse.iconForGroup(group, isDay);
    }

    function labelForGroup(group) {
        return WeatherParse.labelForGroup(group);
    }

    function hasCoords() {
        return !isNaN(root.latitude) && !isNaN(root.longitude);
    }

    /** Try the configured location file first; fall back to IP lookup. */
    function resolveLocation() {
        locationFile.reload();
    }

    function useCoords(lat, lon, name) {
        if (isNaN(lat) || isNaN(lon)) return false;
        var moved = lat !== root.latitude || lon !== root.longitude;
        root.latitude = lat;
        root.longitude = lon;
        if (name) root.locationName = name;
        else if (moved || root.locationName === "") lookupName();
        fetchWeather();
        return true;
    }

    /** Name lookup for coordinates: wttr.in gives the area, Open-Meteo geocoding adds the country code. */
    function lookupName() {
        nameProc.command = ["curl", "-fsS", "--max-time", "10",
            "https://wttr.in/" + root.latitude + "," + root.longitude + "?format=j1"];
        nameProc.running = true;
    }

    function fetchWeather() {
        if (!hasCoords()) return;
        if (weatherProc.running) return;
        root.loading = true;
        weatherProc.command = ["curl", "-fsS", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + root.latitude
            + "&longitude=" + root.longitude
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,dew_point_2m,weather_code,is_day,wind_speed_10m,wind_direction_10m,wind_gusts_10m,surface_pressure"
            + "&hourly=temperature_2m,weather_code,is_day,precipitation_probability,uv_index"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunrise,sunset,daylight_duration,uv_index_max,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant,surface_pressure_mean,apparent_temperature_max,relative_humidity_2m_mean,dew_point_2m_mean"
            + "&timezone=auto&forecast_days=7"];
        weatherProc.running = true;
    }

    FileView {
        id: locationFile
        path: root.locationPath
        printErrors: false
        onLoaded: {
            try {
                var data = JSON.parse(text());
                var lat = parseFloat(data.latitude);
                var lon = parseFloat(data.longitude);
                var name = data.name || data.city || data.location || "";
                if (!root.useCoords(lat, lon, typeof name === "string" ? name : ""))
                    ipLocationProc.running = true;
            } catch (e) {
                ipLocationProc.running = true;
            }
        }
        onLoadFailed: ipLocationProc.running = true
    }

    /** IP-based fallback location, same source Omarchy's own weather panel uses. */
    Process {
        id: ipLocationProc
        command: ["curl", "-fsS", "--max-time", "10", "https://wttr.in/?format=j1"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    var area = data.nearest_area[0];
                    root.useCoords(parseFloat(area.latitude), parseFloat(area.longitude));
                } catch (e) {
                    // No location available; leave the placeholder showing.
                    root.error = "No location";
                }
            }
        }
    }

    /** Area name from wttr.in, then geocoding for "City, CC". */
    Process {
        id: nameProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var area = JSON.parse(text).nearest_area[0];
                    var city = area.areaName[0].value;
                    root.locationName = city + ", " + area.country[0].value;
                    geocodeProc.command = ["curl", "-fsS", "--max-time", "10",
                        "https://geocoding-api.open-meteo.com/v1/search?count=10&format=json&name=" + encodeURIComponent(city)];
                    geocodeProc.running = true;
                } catch (e) {
                    // Keep the name empty; the tab hides it.
                }
            }
        }
    }

    Process {
        id: geocodeProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var place = WeatherParse.placeFromGeocoding(JSON.parse(text).results, root.latitude, root.longitude);
                    if (place !== "") root.locationName = place;
                } catch (e) {
                    // Keep the wttr.in name.
                }
            }
        }
    }

    Process {
        id: weatherProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var m = WeatherParse.parse(JSON.parse(text));
                    var c = m.current;
                    root.model = m;
                    root.temperatureC = c.tempC;
                    root.weatherCode = c.code;
                    root.isDay = c.isDay;
                    root.feelsLikeC = c.feelsLikeC;
                    root.humidity = c.humidity;
                    root.dewPointC = c.dewPointC;
                    root.windKmh = c.windKmh;
                    root.windDirection = c.windDirection;
                    root.gustKmh = c.gustKmh;
                    root.precipMm = c.precipMm;
                    root.precipProbability = c.precipProbability;
                    root.uvIndex = c.uvIndex;
                    root.uvLabel = c.uvLabel;
                    root.pressureHpa = c.pressureHpa;
                    root.sunrise = c.sunrise;
                    root.sunset = c.sunset;
                    root.daylight = c.daylight;
                    root.hours = WeatherParse.nextHours(m);
                    root.days = m.days;
                    root.updatedAt = Date.now();
                    root.error = "";
                    root.ready = true;
                } catch (e) {
                    // Keep the last good data on failure.
                    root.error = "Bad data";
                }
                root.loading = false;
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.error = "Offline";
                root.loading = false;
            }
        }
    }

    Component.onCompleted: resolveLocation()

    Timer {
        id: refreshTimer
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.hasCoords() ? root.fetchWeather() : root.resolveLocation()
    }
}
