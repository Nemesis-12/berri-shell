.pragma library
.import "WeatherFormat.js" as WeatherFormat
.import "Times.js" as Times

// Pure parsing helpers for Weather.qml. No QML types, so node can test them.
// Wall times stay as API text. Instants use the location UTC offset, never the host zone.

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

// One entry for each hour of the response.
function readHours(h, utcOffsetSeconds) {
    var hoursAll = [];
    for (var i = 0; i < h.time.length; i++) {
        hoursAll.push({
            time: h.time[i],
            timeMs: Date.parse(h.time[i] + "Z") - utcOffsetSeconds * 1000,
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
function readDays(d) {
    var days = [];
    for (var j = 0; j < d.time.length; j++) {
        days.push({
            date: d.time[j],
            code: reading(d.weather_code[j]),
            minC: rounded(d.temperature_2m_min[j]),
            maxC: rounded(d.temperature_2m_max[j]),
            precipProbability: reading(d.precipitation_probability_max[j]),
            precipMm: round1(d.precipitation_sum[j]),
            sunrise: WeatherFormat.clock(d.sunrise[j], true),
            sunset: WeatherFormat.clock(d.sunset[j], true),
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

// Index of the current hour in the hourly list (times compare as strings up to the hour).
function currentHourIndex(currentTime, hourTimes) {
    var nowKey = currentTime.substring(0, 13);
    for (var k = 0; k < hourTimes.length; k++) {
        if (hourTimes[k].substring(0, 13) === nowKey) return k;
    }
    return 0;
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

// Builds the whole model from one Open-Meteo response.
// Returns { current, hoursAll, days, nowIndex } where `current` is a detail object (see below).
// Detail objects share these fields: code, tempC, minC, maxC, feelsLikeC, humidity, dewPointC,
// windKmh, windDirection, gustKmh, precipMm, precipProbability, uvIndex, uvLabel, pressureHpa,
// sunrise ("HH:MM"), sunset ("HH:MM"), daylight ("12h 13m"), isDay.
function parse(data) {
    var utcOffsetSeconds = data.utc_offset_seconds;
    var days = readDays(data.daily);
    var nowIndex = currentHourIndex(data.current.time, data.hourly.time);
    var uv = reading(data.hourly.uv_index[nowIndex]);
    return {
        current: readCurrent(data.current, days[0], uv),
        hoursAll: readHours(data.hourly, utcOffsetSeconds),
        utcOffsetSeconds: utcOffsetSeconds,
        days: days,
        nowIndex: nowIndex
    };
}

// Next 24 hours starting at the current hour.
function nextHours(model) {
    return model.hoursAll.slice(model.nowIndex, model.nowIndex + 24);
}

// Detail for day `index`; index 0 is today and uses current values. Other days use their summaries.
function dayDetail(model, index) {
    if (index <= 0 || index >= model.days.length) return model.current;
    var day = model.days[index];
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

// Hours that belong to day `index`; for day 0, from the current hour to the end of today.
function hoursFor(model, index) {
    if (index < 0 || index >= model.days.length) return [];
    var date = model.days[index].date;
    var out = [];
    for (var i = index === 0 ? model.nowIndex : 0; i < model.hoursAll.length; i++) {
        var t = model.hoursAll[i].time;
        if (t.slice(0, 10) === date)
            out.push(model.hoursAll[i]);
    }
    return out;
}

// Hours for the hour strip of day `index`: for today the next 24 hours (they cross midnight), else that day's hours.
function stripHours(model, index) {
    return index === 0 ? nextHours(model) : hoursFor(model, index);
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
