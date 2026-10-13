// Run: node --test berri-shell/tests/weather-parse.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs
  .readFileSync(new URL("../logic/WeatherParse.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, "")
  .replace(/^\.import .*$/gm, "");
const formatSource = fs.readFileSync(new URL("../logic/WeatherFormat.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, "")
  .replace(/^\.import .*$/gm, "");
const lib = vm.createContext({});
const timesSource = fs.readFileSync(new URL("../logic/Times.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, "");
const times = vm.createContext({});
vm.runInContext(timesSource, times);
const format = vm.createContext({ Times: times });
vm.runInContext(formatSource, format);
lib.WeatherFormat = format;
lib.Times = times;
vm.runInContext(source, lib);

// Two days of hourly data is enough to test the slicing.
const hourTimes = [];
for (const day of ["2026-09-30", "2026-10-01"])
  for (let hour = 0; hour < 24; hour++) hourTimes.push(`${day}T${String(hour).padStart(2, "0")}:00`);
const fill = (value) => hourTimes.map(() => value);
const dayFill = (a, b) => [a, b];

const sample = {
  utc_offset_seconds: 0,
  current: { time: "2026-09-30T06:15", temperature_2m: 17.5, apparent_temperature: 19.5, relative_humidity_2m: 96,
    dew_point_2m: 16.8, weather_code: 2, is_day: 0, wind_speed_10m: 2.9, wind_direction_10m: 315,
    wind_gusts_10m: 8.6, surface_pressure: 1004.9 },
  hourly: { time: hourTimes, weather_code: fill(3), is_day: fill(1), temperature_2m: fill(18.4),
    precipitation_probability: fill(10), uv_index: hourTimes.map((_, i) => (i === 6 ? 6.4 : 0)) },
  daily: { time: ["2026-09-30", "2026-10-01"], weather_code: dayFill(3, 61), temperature_2m_min: dayFill(15.2, 14),
    temperature_2m_max: dayFill(22.6, 20), precipitation_probability_max: dayFill(20, 80), precipitation_sum: dayFill(0.34, 5.5),
    sunrise: dayFill("2026-09-30T07:30", "2026-10-01T07:31"), sunset: dayFill("2026-09-30T19:43", "2026-10-01T19:41"),
    daylight_duration: dayFill(43980, 43800), uv_index_max: dayFill(5.2, 3), wind_speed_10m_max: dayFill(14, 30),
    wind_gusts_10m_max: dayFill(30, 55), apparent_temperature_max: dayFill(23, 19), relative_humidity_2m_mean: dayFill(80, 90),
    dew_point_2m_mean: dayFill(15, 16), wind_direction_10m_dominant: dayFill(0, 180), surface_pressure_mean: dayFill(1005, 1000) },
};

test("current values", () => {
  const { current } = lib.parse(sample);
  assert.equal(current.tempC, 18);
  assert.equal(current.windDirection, "NW");
  assert.equal(current.uvIndex, 6.4); // hour 06 of today
  assert.equal(current.uvLabel, "High");
  assert.equal(current.sunrise, "07:30");
  assert.equal(current.daylight, "12h 13m");
  assert.equal(current.precipMm, 0.3);
});

test("hours start at the current hour", () => {
  const model = lib.parse(sample);
  const next = lib.nextHours(model);
  assert.equal(next.length, 24);
  assert.equal(Number(format.hourLabel(next[0].time, true)), 6);
  assert.equal(lib.hoursFor(model, 0).length, 18); // 06:00 to 23:00
  assert.equal(lib.hoursFor(model, 1).length, 24);
});

test("hours strip for today keeps going after midnight", () => {
  const late = { ...sample, current: { ...sample.current, time: "2026-09-30T23:15" } };
  const model = lib.parse(late);
  const strip = lib.stripHours(model, 0);
  assert.equal(strip.length, 24);
  assert.deepEqual(Array.from(strip.slice(0, 6), (h) => Number(format.hourLabel(h.time, true))), [23, 0, 1, 2, 3, 4]);
  const tomorrow = lib.stripHours(model, 1);
  assert.equal(tomorrow.length, 24); // other days: whole day
  assert.ok(tomorrow.every((h) => h.time.startsWith("2026-10-01")));
});

test("day detail", () => {
  const model = lib.parse(sample);
  assert.equal(lib.dayDetail(model, 0), model.current);
  const tomorrow = lib.dayDetail(model, 1);
  assert.equal(tomorrow.tempC, 20);
  assert.equal(tomorrow.windDirection, "S");
  assert.equal(tomorrow.gustKmh, 55);
});

test("uv labels and place picking", () => {
  assert.deepEqual([0, 3, 6, 8, 11].map(lib.uvLabel), ["Low", "Moderate", "High", "Very high", "Extreme"]);
  const results = [{ name: "Oporto", latitude: -22, longitude: 29, country_code: "ZA" },
    { name: "Porto", latitude: 41.1, longitude: -8.6, country_code: "PT" }];
  assert.equal(lib.placeFromGeocoding(results, 41.15, -8.61), "Porto, PT");
  assert.equal(lib.placeFromGeocoding([], 1, 1), "");
});


test("WMO groups, labels and icons", () => {
  const groups = [
    ["clear", [0, 1], "Clear", "sun"],
    ["partlyCloudy", [2], "Partly cloudy", "cloud-sun"],
    ["cloudy", [3, -1, 100], "Cloudy", "cloud"],
    ["fog", [45, 48], "Fog", "cloud"],
    ["drizzle", [51, 53, 55, 56, 57], "Drizzle", "cloud-drizzle"],
    ["rain", [61, 63, 65, 66, 67, 80, 81, 82], "Rain", "cloud-rain"],
    ["snow", [71, 73, 75, 77, 85, 86], "Snow", "cloud-snow"],
    ["thunderstorm", [95, 96, 99], "Thunderstorms", "cloud-lightning"],
  ];
  for (const [group, codes, label, icon] of groups) {
    for (const code of codes) assert.equal(lib.weatherGroup(code), group);
    assert.equal(lib.labelForGroup(group), label);
    assert.equal(lib.iconForGroup(group, true), icon);
    if (group === "snow") assert.equal(lib.iconForGroup(group, false), "cloud-snow");
  }
  assert.equal(lib.iconForGroup("clear", false), "moon");
  assert.equal(lib.iconForGroup("partlyCloudy", false), "cloud-moon");
});

test("shared time and compass helpers keep weather text", () => {
  assert.equal(format.clock("2026-09-30T07:30", true), "07:30");
  assert.equal(format.clock("07:30", false), "7:30 AM");
  assert.equal(format.clock("2026-09-30T19:43", false), "7:43 PM");
  assert.equal(format.hourLabel("2026-09-30T06:00", false), "6A");
  assert.equal(format.toDate("2026-09-30").getUTCDate(), 30);
  assert.equal(format.compass(22.5, 16), "NNE");
  assert.equal(format.compass(22.5), "NE");
  assert.equal(format.compass("NNE"), "NNE");
  assert.equal(format.compass(-45, 16), "NW");
});


test("weather clocks and weekday names keep their display format", () => {
  assert.equal(format.clock("2026-09-30T00:05", false), "12:05 AM");
  assert.equal(format.clock("2026-09-30T12:05", false), "12:05 PM");
  assert.equal(format.clock("2026-09-30T00:05", true), "00:05");
  assert.equal(format.clock(""), "");
  assert.equal(format.hourLabel("2026-09-30T00:00", false), "12A");
  assert.equal(format.hourLabel("2026-09-30T12:00", false), "12P");
  assert.equal(format.hourLabel("2026-09-30T06:00", true), "06");
  assert.equal(format.weekday("2026-09-30"), "WED");
  assert.equal(format.weekday("2026-10-04"), "SUN");
});

// The host changes to DST on March 8; Honolulu keeps UTC minus ten hours.
test("remote clock text and instants use the API offset across host DST", () => {
  const previousZone = process.env.TZ;
  process.env.TZ = "America/Chicago";
  try {
    const remote = structuredClone(sample);
    remote.utc_offset_seconds = -36000;
    remote.current.time = "2026-03-08T02:15";
    remote.hourly.time = hourTimes.map((time) => time.replace("2026-09-30", "2026-03-08").replace("2026-10-01", "2026-03-09"));
    remote.daily.time = ["2026-03-08", "2026-03-09"];
    remote.daily.sunrise = ["2026-03-08T02:30", "2026-03-09T02:30"];
    const model = lib.parse(remote);
    assert.equal(model.utcOffsetSeconds, -36000);
    assert.equal(model.hoursAll[2].timeMs, Date.UTC(2026, 2, 8, 12));
    assert.deepEqual(Array.from(model.hoursAll.slice(1, 4), (hour) => format.hourLabel(hour.time, true)), ["01", "02", "03"]);
    assert.equal(model.days[0].sunrise, "02:30");
    assert.equal(format.weekday(model.days[0].date), "SUN");
    assert.equal(lib.hoursFor(model, 0).length, 22);
  } finally {
    if (previousZone === undefined) delete process.env.TZ;
    else process.env.TZ = previousZone;
  }
});

test("missing current, hourly and daily readings stay missing while zero stays zero", () => {
  const missing = structuredClone(sample);
  for (const field of ["relative_humidity_2m", "dew_point_2m", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m", "surface_pressure", "apparent_temperature"])
    missing.current[field] = null;
  for (const field of ["temperature_2m", "precipitation_probability", "uv_index", "weather_code", "is_day"])
    missing.hourly[field][6] = null;
  for (const field of Object.keys(missing.daily))
    if (field !== "time") missing.daily[field][1] = null;
  const model = lib.parse(missing);
  const current = model.current;
  for (const field of ["humidity", "dewPointC", "windKmh", "gustKmh", "pressureHpa", "feelsLikeC", "uvIndex"])
    assert.equal(current[field], null, field);
  assert.equal(current.windDirection, "");
  assert.equal(current.uvLabel, "");
  assert.equal(model.hoursAll[6].tempC, null);
  assert.equal(model.hoursAll[6].precipProbability, null);
  assert.equal(model.hoursAll[6].isDay, null);
  assert.equal(model.hoursAll[6].code, null);
  const tomorrow = lib.dayDetail(model, 1);
  for (const field of ["tempC", "minC", "maxC", "precipMm", "humidity", "pressureHpa", "uvIndex"])
    assert.equal(tomorrow[field], null, field);
  assert.equal(tomorrow.sunrise, "");
  assert.equal(tomorrow.daylight, "");
  assert.equal(format.number(current.humidity), "-");
  assert.equal(format.millimetres(tomorrow.precipMm), "-");
  assert.equal(format.compass(null), "");
  assert.equal(format.number(0), "0");
  assert.equal(format.millimetres(0), "0");
});

test("a missing current hour fails instead of borrowing midnight UV and hours", () => {
  const missing = structuredClone(sample);
  missing.current.time = "2026-10-02T10:15";
  assert.equal(lib.currentHourIndex(missing.current.time, missing.hourly.time), -1);
  assert.throws(() => lib.parse(missing), /current hour/);
  assert.equal(lib.parse(sample).current.uvIndex, 6.4);
});

test("forecasts require real current conditions, an offset and matching arrays", () => {
  for (const field of ["temperature_2m", "weather_code", "is_day"])
    for (const value of [null, undefined, "0", NaN, Infinity]) {
      const bad = structuredClone(sample);
      bad.current[field] = value;
      assert.throws(() => lib.parse(bad), /current reading/, field);
    }
  for (const offset of [undefined, null, "0", NaN, Infinity]) {
    const bad = structuredClone(sample);
    bad.utc_offset_seconds = offset;
    assert.throws(() => lib.parse(bad), /offset/);
  }
  for (const section of ["hourly", "daily"])
    for (const field of Object.keys(sample[section])) {
      const bad = structuredClone(sample);
      bad[section][field].pop();
      assert.throws(() => lib.parse(bad), /forecast array/, `${section}.${field}`);
    }
  const badTime = structuredClone(sample);
  badTime.hourly.time[2] = "not a time";
  assert.throws(() => lib.parse(badTime), /time/);
  assert.equal(lib.parse(sample).current.tempC, 18);
});

test("a selected date stays selected when the rolling forecast crosses midnight", () => {
  const before = [{ date: "2026-09-30" }, { date: "2026-10-01" }, { date: "2026-10-02" }];
  const after = [{ date: "2026-10-01" }, { date: "2026-10-02" }, { date: "2026-10-03" }];
  assert.equal(lib.selectedDay(before, "2026-10-02"), 2);
  assert.equal(lib.selectedDay(after, "2026-10-02"), 1);
  assert.equal(lib.selectedDay(after, "2026-10-01"), 0);
  assert.equal(lib.selectedDay(after, "2026-09-30"), 0);
  assert.equal(lib.selectedDay([], "2026-10-02"), 0);
  assert.equal(lib.selectedDay(after, ""), 0);
  assert.equal(lib.dayDetail(lib.parse(sample), 7), null);
});
