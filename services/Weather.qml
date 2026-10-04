pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/WeatherParse.js" as WeatherParse

/**
 * Weather data for the pill, the Home cell and the Weather tab. Location comes from Omarchy's own weather
 * settings file; if that is missing or invalid, falls back to wttr.in's IP
 * lookup. Actual conditions come from Open-Meteo. Refreshes every 15 min,
 * resolves location each hour, and retries failed calls after 45 seconds.
 * One Open-Meteo request per refresh gives current values, 7 days and hourly data.
 * On failure the last good data stays and `error` holds a short text.
 * Temperatures are in Celsius.
 * Times: `sunrise`, `sunset` are local "HH:MM" strings; `hours[].time` and `days[].date` are Dates.
 */
Singleton {
    id: root

    readonly property string locationPath: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/settings/weather.json"

    property real latitude: NaN
    property real longitude: NaN
    property bool locationPending: false

    /** True once a real reading has been received at least once. */
    readonly property bool ready: current !== null
    readonly property int temperatureC: current ? current.tempC : 0
    readonly property int weatherCode: current ? current.code : 3
    readonly property bool isDay: current ? current.isDay : true

    /** Short place name, "City, CC". Empty until known. */
    property string locationName: ""
    /** Time (ms since epoch) of the last good fetch; 0 before the first one. */
    property real updatedAt: 0
    property bool loading: false
    /** "" or a short text about the last failed refresh. */
    property string error: ""

    // Other current readouts (same names as dayDetail(0)).
    readonly property int feelsLikeC: current ? current.feelsLikeC : 0
    readonly property int humidity: current ? current.humidity : 0
    readonly property int dewPointC: current ? current.dewPointC : 0
    readonly property int windKmh: current ? current.windKmh : 0
    readonly property string windDirection: current ? current.windDirection : ""
    readonly property int gustKmh: current ? current.gustKmh : 0
    /** Expected precipitation for today, mm. */
    readonly property real precipMm: current ? current.precipMm : 0
    readonly property int precipProbability: current ? current.precipProbability : 0
    readonly property real uvIndex: current ? current.uvIndex : 0
    readonly property string uvLabel: current ? current.uvLabel : "Low"
    readonly property int pressureHpa: current ? current.pressureHpa : 0
    readonly property string sunrise: current ? current.sunrise : ""
    readonly property string sunset: current ? current.sunset : ""
    readonly property string daylight: current ? current.daylight : ""

    /** Next 24 hours from the current hour: { time, code, isDay, tempC, precipProbability }. */
    readonly property var hours: model ? WeatherParse.nextHours(model) : []
    /** 7 days: { date, code, minC, maxC, precipProbability, precipMm, sunrise, sunset, uvMax,
     *  windMaxKmh, gustMaxKmh, humidityMean, dewPointMean, feelsLikeMax }. */
    readonly property var days: model ? model.days : []

    // Parsed model from WeatherParse.parse(); backs dayDetail() and stripHours().
    property var model: null
    // Every current readout comes from this result.
    readonly property var current: model ? model.current : null

    /** Readouts for day `index` (0 = now). Same field names as the current properties, plus tempC, minC, maxC, code. */
    function dayDetail(index) {
        return model ? WeatherParse.dayDetail(model, index) : null;
    }

    /** Hours for the strip of day `index`; for 0, the next 24 hours (they cross midnight). */
    function stripHours(index) {
        return model ? WeatherParse.stripHours(model, index) : [];
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

    // Checks whether a location is available for the next forecast request.
    function hasCoords() {
        return !isNaN(root.latitude) && !isNaN(root.longitude);
    }

    /** Try the configured location file first; fall back to IP lookup. */
    function resolveLocation() {
        root.locationPending = true;
        locationFile.reload();
    }

    // Applies a location read and starts its name and forecast requests.
    function useCoords(lat, lon, name) {
        if (isNaN(lat) || isNaN(lon)) return false;
        var moved = lat !== root.latitude || lon !== root.longitude;
        root.latitude = lat;
        root.longitude = lon;
        root.locationPending = false;
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

    // Starts one forecast request and keeps the last result while it runs.
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
                    if (!root.useCoords(parseFloat(area.latitude), parseFloat(area.longitude)))
                        throw new Error("No coordinates");
                } catch (e) {
                    // No location available; leave the placeholder showing.
                    root.error = "No location";
                    retryTimer.restart();
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
                    root.model = m;
                    root.updatedAt = Date.now();
                    root.error = "";
                    retryTimer.stop();
                } catch (e) {
                    // Keep the last good data on failure.
                    root.error = "Bad data";
                    retryTimer.restart();
                }
                root.loading = false;
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.error = "Offline";
                root.loading = false;
                retryTimer.restart();
            }
        }
    }

    Component.onCompleted: resolveLocation()

    // Leaves time for a location call and a forecast call within 70 seconds.
    Timer {
        id: retryTimer
        interval: 45 * 1000
        onTriggered: root.locationPending || !root.hasCoords() ? root.resolveLocation() : root.fetchWeather()
    }

    Timer {
        id: refreshTimer
        property int forecastTicks: 0
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        onTriggered: {
            forecastTicks++;
            if (forecastTicks === 4) {
                forecastTicks = 0;
                root.resolveLocation();
            } else if (root.hasCoords()) root.fetchWeather();
            else root.resolveLocation();
        }
    }
}
