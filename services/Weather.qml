pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/WeatherParse.js" as WeatherParse
import "../logic/SourceFailures.js" as SourceFailures

/**
 * Weather data for the pill, the Home cell and the Weather tab. Location comes from Omarchy's own weather
 * settings file; if that is missing or invalid, falls back to wttr.in's IP
 * lookup. Actual conditions come from Open-Meteo. Refreshes every 15 min,
 * resolves location each hour, and retries failed calls after 45 seconds.
 * One Open-Meteo request per refresh gives current values, 7 days and hourly data.
 * On failure the last good data stays and `error` holds a short text: "Offline",
 * "Bad data" or "No location". The views dim the readout and show the age of the
 * data while `error` is set. A failure also writes one line to the shell log
 * (name and fixed reason only). The next line comes at the earliest one hour
 * later (SourceFailures.PERIOD_MS), however many retries fail.
 * Temperatures are in Celsius.
 * Times: `sunrise`, `sunset` are local "HH:MM" strings; `hours[].time` and `days[].date` are API wall-time text.
 */
Singleton {
    id: root

    readonly property string locationPath: FolderRoots.weatherSettings

    property real latitude: NaN
    property real longitude: NaN
    property bool locationPending: false
    // Each coordinate change makes all earlier request replies obsolete.
    property int locationRevision: 0
    property bool forecastPending: false
    property bool namePending: false
    property string pendingCity: ""

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

    /** Last log line time of each source (see SourceFailures.js). */
    property var lastLogged: ({})

    /** Writes the failure line unless one was written in this period. */
    function logFailure(reason, source) {
        var line = SourceFailures.report(root.lastLogged, source || "weather", reason, Date.now());
        if (line !== "") console.warn(line);
    }

    // Other current readouts (same names as dayDetail(0)).
    readonly property var feelsLikeC: current ? current.feelsLikeC : null
    readonly property var humidity: current ? current.humidity : null
    readonly property var dewPointC: current ? current.dewPointC : null
    readonly property var windKmh: current ? current.windKmh : null
    readonly property string windDirection: current ? current.windDirection : ""
    readonly property var gustKmh: current ? current.gustKmh : null
    /** Expected precipitation for today, mm. */
    readonly property var precipMm: current ? current.precipMm : null
    readonly property var precipProbability: current ? current.precipProbability : null
    readonly property var uvIndex: current ? current.uvIndex : null
    readonly property string uvLabel: current ? current.uvLabel : ""
    readonly property var pressureHpa: current ? current.pressureHpa : null
    readonly property string sunrise: current ? current.sunrise : ""
    readonly property string sunset: current ? current.sunset : ""
    readonly property string daylight: current ? current.daylight : ""

    /** Next 24 hours from the current hour: { time, code, isDay, tempC, precipProbability }. */
    readonly property var hours: model ? WeatherParse.nextHours(model, Clock.minute.getTime()) : []
    /** 7 days: { date, code, minC, maxC, precipProbability, precipMm, sunrise, sunset, uvMax,
     *  windMaxKmh, gustMaxKmh, humidityMean, dewPointMean, feelsLikeMax }. */
    readonly property var days: model ? model.days : []

    // Parsed model from WeatherParse.parse(); backs dayDetail() and stripHours().
    property var model: null
    // Every current readout comes from this result.
    readonly property var current: model ? model.current : null

    /** Readouts for day `index` (0 = now). Same field names as the current properties, plus tempC, minC, maxC, code. */
    function dayDetail(index) {
        // Bind the caller to successful forecast changes, including changes inside the model.
        void root.updatedAt;
        return model ? WeatherParse.dayDetail(model, index) : null;
    }

    /** Hours for the strip of day `index`; for 0, the next 24 hours (they cross midnight). */
    function stripHours(index, now) {
        // Use the same forecast dependency as dayDetail().
        void root.updatedAt;
        return model ? WeatherParse.stripHours(model, index, now === undefined ? Clock.minute.getTime() : now) : [];
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
        if (moved) {
            root.locationRevision++;
            root.model = null;
            root.updatedAt = 0;
            root.error = "";
            root.locationName = "";
            root.pendingCity = "";
        }
        root.latitude = lat;
        root.longitude = lon;
        root.locationPending = false;
        if (name) root.locationName = name;
        else if (moved || root.locationName === "") lookupName();
        fetchWeather();
        return true;
    }

    // Starts the fallback only when no earlier IP request is still running.
    function lookupIp() {
        if (ipLocationProc.running) return;
        ipLocationProc.locationRevision = root.locationRevision;
        ipLocationProc.running = true;
    }

    /** Name lookup for coordinates: wttr.in gives the area, Open-Meteo geocoding adds the country code. */
    function lookupName() {
        if (nameProc.running) {
            root.namePending = true;
            return;
        }
        root.namePending = false;
        nameProc.locationRevision = root.locationRevision;
        nameProc.command = ["curl", "-fsS", "--max-time", "10",
            "https://wttr.in/" + root.latitude + "," + root.longitude + "?format=j1"];
        nameProc.running = true;
    }

    // Refines the current place name; an older lookup cannot overwrite it.
    function lookupCountry(city, revision) {
        if (revision !== root.locationRevision) return;
        if (geocodeProc.running) {
            root.pendingCity = city;
            return;
        }
        geocodeProc.locationRevision = revision;
        geocodeProc.command = ["curl", "-fsS", "--max-time", "10",
            "https://geocoding-api.open-meteo.com/v1/search?count=10&format=json&name=" + encodeURIComponent(city)];
        geocodeProc.running = true;
    }

    // Starts one forecast request and keeps the last result while it runs.
    function fetchWeather() {
        if (!hasCoords()) return;
        if (weatherProc.running) {
            root.forecastPending = true;
            return;
        }
        root.forecastPending = false;
        weatherProc.locationRevision = root.locationRevision;
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
                    root.lookupIp();
            } catch (e) {
                root.lookupIp();
            }
        }
        onLoadFailed: root.lookupIp()
    }

    /** IP-based fallback location, same source Omarchy's own weather panel uses. */
    Process {
        id: ipLocationProc
        property int locationRevision: -1
        command: ["curl", "-fsS", "--max-time", "10", "https://wttr.in/?format=j1"]
        stdout: StdioCollector { waitForEnd: true }
        onExited: (code) => {
            if (locationRevision !== root.locationRevision || !root.locationPending) return;
            try {
                if (code !== 0) throw new Error("Offline");
                var area = JSON.parse(stdout.text).nearest_area[0];
                if (!root.useCoords(parseFloat(area.latitude), parseFloat(area.longitude)))
                    throw new Error("No coordinates");
            } catch (e) {
                root.error = code !== 0 ? "Offline" : "No location";
                root.logFailure(code !== 0 ? "offline" : "no location");
                retryTimer.restart();
            }
        }
    }

    /** Area name from wttr.in, then geocoding for "City, CC". */
    Process {
        id: nameProc
        property int locationRevision: -1
        stdout: StdioCollector { waitForEnd: true }
        onExited: (code) => {
            if (locationRevision === root.locationRevision) {
                try {
                    if (code !== 0) throw new Error("Offline");
                    var area = JSON.parse(stdout.text).nearest_area[0];
                    var city = area.areaName[0].value;
                    var country = area.country[0].value;
                    if (typeof city !== "string" || city === "" || typeof country !== "string")
                        throw new Error("Bad name");
                    root.locationName = city + (country ? ", " + country : "");
                    root.lookupCountry(city, locationRevision);
                } catch (e) {
                    root.logFailure(code !== 0 ? "offline" : "bad data", "weather name");
                }
            }
            if (root.namePending && root.locationName === "") Qt.callLater(root.lookupName);
            root.namePending = false;
        }
    }

    Process {
        id: geocodeProc
        property int locationRevision: -1
        stdout: StdioCollector { waitForEnd: true }
        onExited: (code) => {
            if (locationRevision === root.locationRevision) {
                try {
                    if (code !== 0) throw new Error("Offline");
                    var results = JSON.parse(stdout.text).results;
                    if (results !== undefined && !Array.isArray(results)) throw new Error("Bad places");
                    var place = WeatherParse.placeFromGeocoding(results, root.latitude, root.longitude);
                    if (place !== "") root.locationName = place;
                    else root.logFailure("no location", "weather geocoding");
                } catch (e) {
                    root.logFailure(code !== 0 ? "offline" : "bad data", "weather geocoding");
                }
            }
            if (root.pendingCity !== "") Qt.callLater(root.lookupCountry, root.pendingCity, root.locationRevision);
            root.pendingCity = "";
        }
    }

    Process {
        id: weatherProc
        property int locationRevision: -1
        stdout: StdioCollector { waitForEnd: true }
        onExited: (code) => {
            if (locationRevision === root.locationRevision) {
                try {
                    if (code !== 0) throw new Error("Offline");
                    root.model = WeatherParse.parse(JSON.parse(stdout.text));
                    root.updatedAt = Date.now();
                    root.error = "";
                    retryTimer.stop();
                } catch (e) {
                    root.error = code !== 0 ? "Offline" : "Bad data";
                    root.logFailure(code !== 0 ? "offline" : "bad data");
                    retryTimer.restart();
                }
                root.loading = false;
            }
            if (root.forecastPending || locationRevision !== root.locationRevision)
                Qt.callLater(root.fetchWeather);
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
