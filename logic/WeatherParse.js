.pragma library
.import "WeatherFormat.js" as WeatherFormat
.import "Times.js" as Times

// Pure parsing helpers for Weather.qml. No QML types, so node can test them.
// Open-Meteo times are local to the place ("2026-09-30T06:15"); they are read as system-local Dates.

function uvLabel(uv) {
    if (uv < 3) return "Low";
    if (uv < 6) return "Moderate";
    if (uv < 8) return "High";
    if (uv < 11) return "Very high";
    return "Extreme";
}

// Seconds -> "12h 13m".
var daylightWording = { round: true, pad: false, days: false, lower: true };

function round1(value) {
    return Math.round(value * 10) / 10;
}

// One entry for each hour of the response.
function readHours(h) {
    var hoursAll = [];
    for (var i = 0; i < h.time.length; i++) {
        hoursAll.push({
            time: WeatherFormat.toDate(h.time[i]),
            code: h.weather_code[i],
            isDay: h.is_day[i] === 1,
            tempC: Math.round(h.temperature_2m[i]),
            precipProbability: h.precipitation_probability[i] || 0,
            uvIndex: h.uv_index[i] || 0
        });
    }
    return hoursAll;
}

// One summary for each day of the response.
function readDays(d) {
    var days = [];
    for (var j = 0; j < d.time.length; j++) {
        days.push({
            date: WeatherFormat.toDate(d.time[j] + "T00:00"),
            code: d.weather_code[j],
            minC: Math.round(d.temperature_2m_min[j]),
            maxC: Math.round(d.temperature_2m_max[j]),
            precipProbability: d.precipitation_probability_max[j] || 0,
            precipMm: round1(d.precipitation_sum[j] || 0),
            sunrise: WeatherFormat.clock(d.sunrise[j], true),
            sunset: WeatherFormat.clock(d.sunset[j], true),
            uvMax: round1(d.uv_index_max[j] || 0),
            windMaxKmh: Math.round(d.wind_speed_10m_max[j]),
            gustMaxKmh: Math.round(d.wind_gusts_10m_max[j]),
            humidityMean: Math.round(d.relative_humidity_2m_mean[j]),
            dewPointMean: Math.round(d.dew_point_2m_mean[j]),
            feelsLikeMax: Math.round(d.apparent_temperature_max[j]),
            windDirection: WeatherFormat.compass(d.wind_direction_10m_dominant[j], 16),
            pressureHpa: Math.round(d.surface_pressure_mean[j]),
            daylight: Times.duration(d.daylight_duration[j], daylightWording)
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
        tempC: Math.round(cur.temperature_2m),
        minC: today.minC,
        maxC: today.maxC,
        feelsLikeC: Math.round(cur.apparent_temperature),
        humidity: Math.round(cur.relative_humidity_2m),
        dewPointC: Math.round(cur.dew_point_2m),
        windKmh: Math.round(cur.wind_speed_10m),
        windDirection: WeatherFormat.compass(cur.wind_direction_10m, 16),
        gustKmh: Math.round(cur.wind_gusts_10m),
        precipMm: today.precipMm,
        precipProbability: today.precipProbability,
        uvIndex: round1(uv),
        uvLabel: uvLabel(uv),
        pressureHpa: Math.round(cur.surface_pressure),
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
    var days = readDays(data.daily);
    var nowIndex = currentHourIndex(data.current.time, data.hourly.time);
    var uv = data.hourly.uv_index[nowIndex] || 0;
    return {
        current: readCurrent(data.current, days[0], uv),
        hoursAll: readHours(data.hourly),
        days: days,
        nowIndex: nowIndex
    };
}

// Next 24 hours starting at the current hour.
function nextHours(model) {
    return model.hoursAll.slice(model.nowIndex, model.nowIndex + 24);
}

// Detail for day `index`; 0 = current values. Other days use the day's summary values.
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
        if (t.getFullYear() === date.getFullYear() && t.getMonth() === date.getMonth() && t.getDate() === date.getDate())
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
