.pragma library
.import "WeatherFormat.js" as WeatherFormat
.import "Times.js" as Times

// Pure parsing helpers for Weather.qml. No QML types, so node can test them.
// The request asks for unix seconds, so every instant is exact. Wall text ("2026-10-25T02:00") is
// built with the location offset, never the host zone. The offset of each day comes from the gaps
// between local midnights, so a clock change inside the forecast moves the later days by one hour.
// Text times (wall time and the response UTC offset) are accepted too.

function uvLabel(uv) {
    if (uv === null) return "";
    if (uv < 3) return "Low";
    if (uv < 6) return "Moderate";
    if (uv < 8) return "High";
    if (uv < 11) return "Very high";
    return "Extreme";
}

// Seconds -> "12h 13m".
var daylightWording = { round: true, pad: false, days: false, lower: true };

// Keeps missing API numbers separate from measured zero.
function reading(value) {
    return typeof value === "number" && isFinite(value) ? value : null;
}

// Rounds an API reading without converting missing data to zero.
function rounded(value) {
    var number = reading(value);
    return number === null ? null : Math.round(number);
}

// Rounds millimetres and UV readings to one decimal place.
function round1(value) {
    var number = reading(value);
    return number === null ? null : Math.round(number * 10) / 10;
}

var dayMs = 24 * 60 * 60 * 1000;

// Instant (ms) of an API time: unix seconds, or wall text at the response UTC offset.
function instantOf(value, utcOffsetSeconds) {
    if (typeof value === "number") return value * 1000;
    return Date.parse(value + "Z") - utcOffsetSeconds * 1000;
}

// Wall text "YYYY-MM-DDTHH:MM" of an instant at the given offset.
function wallText(ms, offsetSeconds) {
    return new Date(ms + offsetSeconds * 1000).toISOString().slice(0, 16);
}

// Offset change (seconds) that a day of this length ends with: +3600 for a 23 h day, -3600 for a 25 h day.
function dayShift(length) {
    return (dayMs - length) / 1000;
}

// Instant of the clock change inside a day that is not 24 h long. The response has no time zone
// rules, so this assumes the usual rule: the clock reads 02:00 before the spring change and 03:00
// before the autumn change. A zone with another rule shows one wrong label text near the change.
function changeInstant(start, length) {
    return start + (length < dayMs ? 2 : 3) * 60 * 60 * 1000;
}

// UTC offset (seconds) in force at the start of each day. The response offset belongs to `nowMs`;
// the length of each day (23 h, 24 h or 25 h) moves the offset of its neighbours.
function dayOffsets(starts, nowMs, utcOffsetSeconds) {
    var anchor = 0;
    for (var i = 0; i < starts.length; i++) {
        if (starts[i] <= nowMs) anchor = i;
    }
    var offsets = [];
    var anchorLength = anchor + 1 < starts.length ? starts[anchor + 1] - starts[anchor] : dayMs;
    var passedChange = anchorLength !== dayMs && nowMs >= changeInstant(starts[anchor], anchorLength);
    offsets[anchor] = passedChange ? utcOffsetSeconds - dayShift(anchorLength) : utcOffsetSeconds;
    for (var next = anchor + 1; next < starts.length; next++)
        offsets[next] = offsets[next - 1] + dayShift(starts[next] - starts[next - 1]);
    for (var before = anchor - 1; before >= 0; before--)
        offsets[before] = offsets[before + 1] - dayShift(starts[before + 1] - starts[before]);
    return offsets;
}

// Reads the day starts of the response into a lookup of offsets by instant.
// Text times carry one offset, so every instant gets the response offset.
function readZone(data, nowMs) {
    var utc = data.utc_offset_seconds;
    var times = data.daily.time;
    if (typeof times[0] !== "number")
        return { offsetAt: function() { return utc; } };
    var starts = times.map(function(t) { return t * 1000; });
    var offsets = dayOffsets(starts, nowMs, utc);
    return {
        offsetAt: function(ms) {
            var day = 0;
            for (var i = 0; i < starts.length; i++) {
                if (starts[i] <= ms) day = i;
            }
            if (day + 1 < starts.length) {
                var length = starts[day + 1] - starts[day];
                if (length !== dayMs && ms >= changeInstant(starts[day], length))
                    return offsets[day] + dayShift(length);
            }
            return offsets[day];
        }
    };
}

// Wall text of an API time at its own offset; a missing time stays missing.
function wallOf(value, zone) {
    if (typeof value !== "number") return value;
    return wallText(value * 1000, zone.offsetAt(value * 1000));
}

// One entry for each hour of the response.
function readHours(h, zone, utcOffsetSeconds) {
    var hoursAll = [];
    for (var i = 0; i < h.time.length; i++) {
        hoursAll.push({
            time: wallOf(h.time[i], zone),
            timeMs: instantOf(h.time[i], utcOffsetSeconds),
            code: reading(h.weather_code[i]),
            isDay: reading(h.is_day[i]) === null ? null : h.is_day[i] === 1,
            tempC: rounded(h.temperature_2m[i]),
            precipProbability: reading(h.precipitation_probability[i]),
            uvIndex: reading(h.uv_index[i])
        });
    }
    return hoursAll;
}

// One summary for each day of the response.
function readDays(d, zone, utcOffsetSeconds) {
    var days = [];
    for (var j = 0; j < d.time.length; j++) {
        var startMs = instantOf(d.time[j], utcOffsetSeconds);
        days.push({
            date: wallOf(d.time[j], zone).slice(0, 10),
            startMs: startMs,
            endMs: j + 1 < d.time.length ? instantOf(d.time[j + 1], utcOffsetSeconds) : startMs + dayMs,
            code: reading(d.weather_code[j]),
            minC: rounded(d.temperature_2m_min[j]),
            maxC: rounded(d.temperature_2m_max[j]),
            precipProbability: reading(d.precipitation_probability_max[j]),
            precipMm: round1(d.precipitation_sum[j]),
            sunrise: WeatherFormat.clock(wallOf(d.sunrise[j], zone), true),
            sunset: WeatherFormat.clock(wallOf(d.sunset[j], zone), true),
            uvMax: round1(d.uv_index_max[j]),
            windMaxKmh: rounded(d.wind_speed_10m_max[j]),
            gustMaxKmh: rounded(d.wind_gusts_10m_max[j]),
            humidityMean: rounded(d.relative_humidity_2m_mean[j]),
            dewPointMean: rounded(d.dew_point_2m_mean[j]),
            feelsLikeMax: rounded(d.apparent_temperature_max[j]),
            windDirection: WeatherFormat.compass(d.wind_direction_10m_dominant[j], 16),
            pressureHpa: rounded(d.surface_pressure_mean[j]),
            daylight: reading(d.daylight_duration[j]) === null ? "" : Times.duration(d.daylight_duration[j], daylightWording)
        });
    }
    return days;
}

// Index of the hour that holds an instant, or -1.
function hourIndexAtInstant(hoursAll, now) {
    for (var i = 0; i < hoursAll.length; i++) {
        if (now >= hoursAll[i].timeMs && now < hoursAll[i].timeMs + 60 * 60 * 1000) return i;
    }
    return -1;
}

// Current readings from the response, with today's range, rain, sun and daylight from the day summary.
function readCurrent(cur, today, uv) {
    return {
        code: cur.weather_code,
        isDay: cur.is_day === 1,
        tempC: rounded(cur.temperature_2m),
        minC: today.minC,
        maxC: today.maxC,
        feelsLikeC: rounded(cur.apparent_temperature),
        humidity: rounded(cur.relative_humidity_2m),
        dewPointC: rounded(cur.dew_point_2m),
        windKmh: rounded(cur.wind_speed_10m),
        windDirection: WeatherFormat.compass(cur.wind_direction_10m, 16),
        gustKmh: rounded(cur.wind_gusts_10m),
        precipMm: today.precipMm,
        precipProbability: today.precipProbability,
        uvIndex: round1(uv),
        uvLabel: uvLabel(uv),
        pressureHpa: rounded(cur.surface_pressure),
        sunrise: today.sunrise,
        sunset: today.sunset,
        daylight: today.daylight
    };
}

// Checks the requested API arrays before any readings enter the model.
function checkArrays(section, fields, dateOnly) {
    if (!section || !Array.isArray(section.time) || section.time.length === 0)
        throw new Error("Missing forecast array");
    for (var field of fields) {
        if (!Array.isArray(section[field]) || section[field].length !== section.time.length)
            throw new Error("Mismatched forecast array");
    }
    for (var time of section.time) {
        if (typeof time === "number") {
            if (!isFinite(time)) throw new Error("Invalid forecast time");
            continue;
        }
        var pattern = dateOnly ? /^\d{4}-\d{2}-\d{2}$/ : /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/;
        var date = WeatherFormat.toDate(time);
        if (typeof time !== "string" || !pattern.test(time) || isNaN(date.getTime())
            || date.toISOString().slice(0, time.length) !== time)
            throw new Error("Invalid forecast time");
    }
}

// Rejects responses that cannot supply current conditions or a time basis.
function checkForecast(data) {
    if (reading(data.utc_offset_seconds) === null) throw new Error("Missing UTC offset");
    var cur = data.current;
    if (!cur || reading(cur.temperature_2m) === null || reading(cur.weather_code) === null
        || (cur.is_day !== 0 && cur.is_day !== 1))
        throw new Error("Missing current reading");
    if (typeof cur.time === "number" ? !isFinite(cur.time)
        : typeof cur.time !== "string" || isNaN(WeatherFormat.toDate(cur.time).getTime()))
        throw new Error("Invalid current time");
    checkArrays(data.hourly, ["weather_code", "is_day", "temperature_2m", "precipitation_probability", "uv_index"], false);
    checkArrays(data.daily, ["weather_code", "temperature_2m_min", "temperature_2m_max", "precipitation_probability_max",
        "precipitation_sum", "sunrise", "sunset", "uv_index_max", "wind_speed_10m_max", "wind_gusts_10m_max",
        "relative_humidity_2m_mean", "dew_point_2m_mean", "apparent_temperature_max", "wind_direction_10m_dominant",
        "surface_pressure_mean", "daylight_duration"], true);
}

// Builds the whole model from one Open-Meteo response.
// Returns { current, hoursAll, days, nowIndex } where `current` is a detail object (see below).
// Detail objects share these fields: code, tempC, minC, maxC, feelsLikeC, humidity, dewPointC,
// windKmh, windDirection, gustKmh, precipMm, precipProbability, uvIndex, uvLabel, pressureHpa,
// sunrise ("HH:MM"), sunset ("HH:MM"), daylight ("12h 13m"), isDay.
function parse(data) {
    checkForecast(data);
    var utcOffsetSeconds = data.utc_offset_seconds;
    var nowMs = instantOf(data.current.time, utcOffsetSeconds);
    var zone = readZone(data, nowMs);
    var days = readDays(data.daily, zone, utcOffsetSeconds);
    var hoursAll = readHours(data.hourly, zone, utcOffsetSeconds);
    var nowIndex = hourIndexAtInstant(hoursAll, nowMs);
    if (nowIndex < 0) throw new Error("Missing current hour");
    var uv = reading(data.hourly.uv_index[nowIndex]);
    return {
        current: readCurrent(data.current, days[0], uv),
        hoursAll: hoursAll,
        utcOffsetSeconds: utcOffsetSeconds,
        days: days,
        nowIndex: nowIndex
    };
}

// Finds the location's current hour from an absolute clock instant.
function hourIndexAt(model, now) {
    return hourIndexAtInstant(model.hoursAll, now);
}

// Next 24 hours at the supplied clock instant, or the response time in parser callers.
function nextHours(model, now) {
    var index = now === undefined ? model.nowIndex : hourIndexAt(model, now);
    if (index < 0) return [];
    return model.hoursAll.slice(index, index + 24);
}

// Index of the day that holds an instant; 0 when the forecast does not reach it.
function dayIndexAt(model, now) {
    for (var i = 0; i < model.days.length; i++) {
        if (now >= model.days[i].startMs && now < model.days[i].endMs) return i;
    }
    return 0;
}

// Detail for day `index`; index 0 is the location's today. It uses current values while the
// response still describes today, and the summary of the matching day after midnight.
function dayDetail(model, index, now) {
    if (index < 0 || index >= model.days.length) return null;
    var today = now === undefined ? 0 : dayIndexAt(model, now);
    if (index === 0 && today === 0) return model.current;
    var day = model.days[index === 0 ? today : index];
    return {
        code: day.code,
        isDay: true,
        tempC: day.maxC,
        minC: day.minC,
        maxC: day.maxC,
        feelsLikeC: day.feelsLikeMax,
        humidity: day.humidityMean,
        dewPointC: day.dewPointMean,
        windKmh: day.windMaxKmh,
        windDirection: day.windDirection,
        gustKmh: day.gustMaxKmh,
        precipMm: day.precipMm,
        precipProbability: day.precipProbability,
        uvIndex: day.uvMax,
        uvLabel: uvLabel(day.uvMax),
        pressureHpa: day.pressureHpa,
        sunrise: day.sunrise,
        sunset: day.sunset,
        daylight: day.daylight
    };
}

// Resolves a chosen calendar date in the rolling forecast; absent dates use today.
function selectedDay(days, date) {
    for (var i = 0; i < days.length; i++) {
        if (days[i].date === date) return i;
    }
    return 0;
}

// Hours that belong to day `index`.
function hoursFor(model, index) {
    if (index < 0 || index >= model.days.length) return [];
    var date = model.days[index].date;
    var out = [];
    for (var i = 0; i < model.hoursAll.length; i++) {
        var t = model.hoursAll[i].time;
        if (t.slice(0, 10) === date)
            out.push(model.hoursAll[i]);
    }
    return out;
}

// Strip hours: today continues across midnight; later days sample the mock's daytime hours.
function stripHours(model, index, now) {
    if (index === 0) return nextHours(model, now);
    // Mock 5C uses six samples: 06, 09, 12, 15, 18 and 21.
    return hoursFor(model, index).filter(function(hour) {
        var clockHour = parseInt(hour.time.slice(11, 13));
        return clockHour >= 6 && clockHour <= 21 && (clockHour - 6) % 3 === 0;
    });
}

// Picks "City, CC" from Open-Meteo geocoding results: the hit nearest to the coordinates.
function placeFromGeocoding(results, lat, lon) {
    var best = null;
    var bestDistance = Infinity;
    for (var i = 0; i < (results || []).length; i++) {
        var r = results[i];
        var dist = Math.pow(r.latitude - lat, 2) + Math.pow(r.longitude - lon, 2);
        if (dist < bestDistance) { best = r; bestDistance = dist; }
    }
    if (!best || bestDistance > 1) return "";
    return best.name + (best.country_code ? ", " + best.country_code : "");
}

/** Buckets a WMO weather_code into one of the condition groups the icon/label share. */
function weatherGroup(code) {
    if (code === null || code === undefined) return "unknown";
    if (code === 0 || code === 1) return "clear";
    if (code === 2) return "partlyCloudy";
    if (code === 45 || code === 48) return "fog";
    if (code >= 51 && code <= 57) return "drizzle";
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return "rain";
    if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "snow";
    if (code >= 95 && code <= 99) return "thunderstorm";
    return "cloudy";
}

function iconForGroup(group, isDay) {
    switch (group) {
        case "clear": return isDay ? "sun" : "moon";
        case "partlyCloudy": return isDay ? "cloud-sun" : "cloud-moon";
        case "drizzle": return "cloud-drizzle";
        case "rain": return "cloud-rain";
        case "snow": return "cloud-snow";
        case "thunderstorm": return "cloud-lightning";
        default: return "cloud"; // cloudy, fog
    }
}

function labelForGroup(group) {
    switch (group) {
        case "unknown": return "-";
        case "clear": return "Clear";
        case "partlyCloudy": return "Partly cloudy";
        case "fog": return "Fog";
        case "drizzle": return "Drizzle";
        case "rain": return "Rain";
        case "snow": return "Snow";
        case "thunderstorm": return "Thunderstorms";
        default: return "Cloudy";
    }
}

// How many times the 45 s retry wait to use after `failures` failed tries in a row: 1, 2, 4, 8, 16, then 20 (15 min).
function retryFactor(failures) {
    return Math.min(Math.pow(2, failures), 20);
}
