import QtQuick
import QtTest
import Quickshell.Io
import qs.services
import qs.tabs.code

// The limit meters of the Code tab show a reading only while its source is fresh. The clock is fake:
// a test sets AgentUsage.now after the answer arrives.
Item {
    id: host
    width: 800
    height: 600

    Item { visible: false; width: 800; height: 500
        CodeTab { id: codeTab; anchors.fill: parent }
    }

    CodeLimitMeter { id: meter; width: 82; height: 200; name: "Session" }

    CachedSource { id: freshSource; name: "fresh"; script: "t.py"; versionKey: "version"; age: 600000 }
    CachedSource { id: staleSource; name: "stale"; script: "t.py"; versionKey: "version"; age: 600000 }

    TestCase {
        name: "CodeUsage"
        when: windowShown

        readonly property date start: new Date("2026-10-14T12:00:00Z")
        readonly property string farReset: "2099-01-01T00:00:00Z"

        function cleanup() {
            ProcessLog.scriptAnswer = "";
            AgentUsage.viewers = 0;
            AgentUsage.claudeFetchedAt = "";
            AgentUsage.codexFetchedAt = "";
        }

        // The script answer: Claude 11 and 22 percent, Codex 33 and 44 percent.
        function answer(claudeAt, codexAt) {
            const bucket = percent => ({ percent: percent, resetsAt: farReset });
            return JSON.stringify({
                cacheSeconds: 300,
                claude: { session: bucket(11), weekly: bucket(22), fetchedAt: claudeAt.toISOString() },
                codex: { session: bucket(33), weekly: bucket(44), fetchedAt: codexAt.toISOString() },
            });
        }

        // Lets the service fetch `text`, then sets the fake clock to `now`.
        function load(text, now) {
            AgentUsage.claudeFetchedAt = "";
            ProcessLog.scriptAnswer = text;
            if (AgentUsage.viewers === 0) AgentUsage.viewers = 1;
            else AgentUsage.refresh();
            tryVerify(() => AgentUsage.claudeFetchedAt !== "" && !usageRunning());
            AgentUsage.now = now;
        }

        function usageRunning() {
            return Array.from(AgentUsage.data).find(o => o.command !== undefined).running;
        }

        function minutesAfter(date, minutes) { return new Date(date.getTime() + minutes * 60000); }

        function values() {
            return [AgentUsage.claudeSessionValue, AgentUsage.claudeWeeklyValue,
                    AgentUsage.codexSessionValue, AgentUsage.codexWeeklyValue];
        }

        // Every item below `item` that has `property`, in tree order.
        function findAll(item, property) {
            let found = [];
            for (const child of item.children) {
                if (child[property] !== undefined) found.push(child);
                found = found.concat(findAll(child, property));
            }
            return found;
        }

        function test_a_cached_reading_stays_known_until_the_next_real_fetch_is_late() {
            // The script returns its cache while the reading is under 5 minutes old, and a refresh comes every 5 minutes.
            load(answer(start, start), start);
            compare(AgentUsage.claudeSessionValue, 11);
            AgentUsage.now = minutesAfter(start, 6);
            compare(AgentUsage.claudeSessionValue, 11);
            AgentUsage.now = minutesAfter(start, 14);
            compare(AgentUsage.claudeSessionValue, 11);
            AgentUsage.now = minutesAfter(start, 16);
            compare(AgentUsage.claudeSessionValue, -1);
        }

        function test_each_value_reads_the_freshness_of_its_own_provider() {
            load(answer(start, minutesAfter(start, -30)), start);
            compare(values(), [11, 22, -1, -1]);
            load(answer(minutesAfter(start, -30), start), start);
            compare(values(), [-1, -1, 33, 44]);
        }

        function test_a_reading_fetched_after_the_last_clock_tick_is_known_at_once() {
            load(answer(start, start), start);
            AgentUsage.now = new Date(Date.now() - 30000);
            const fetchedAt = new Date();
            ProcessLog.scriptAnswer = answer(fetchedAt, fetchedAt);
            AgentUsage.refresh();
            tryCompare(AgentUsage, "claudeFetchedAt", fetchedAt.toISOString());
            compare(AgentUsage.claudeSessionValue, 11);
            compare(AgentUsage.codexWeeklyValue, 44);
        }

        function test_the_code_tab_shows_the_values_of_the_picked_agent() {
            load(answer(start, minutesAfter(start, -30)), start);
            codeTab.agent = "claude";
            compare([codeTab.sessionPercent, codeTab.weeklyPercent], [11, 22]);
            codeTab.agent = "codex";
            compare([codeTab.sessionPercent, codeTab.weeklyPercent], [-1, -1]);
            const meters = findAll(codeTab, "fillShare");
            compare(meters.length, 2);
            compare([meters[0].percent, meters[1].percent], [-1, -1]);
            codeTab.agent = "claude";
            compare([meters[0].percent, meters[1].percent], [11, 22]);
        }

        // The running timers of a source that are not the 120 s run limit.
        function wakeTimers(source) {
            return Array.from(source.data).filter(o => o.toString().indexOf("QQmlTimer") === 0 && o.running
                                                        && o.interval !== source.runLimit);
        }

        function test_a_source_knows_if_its_answer_is_valid_and_fresh_without_a_clock_timer() {
            compare([freshSource.valid, freshSource.isFresh()], [false, false]);
            ProcessLog.scriptAnswer = JSON.stringify({ version: Date.now() });
            freshSource.open();
            tryVerify(() => freshSource.valid);
            ProcessLog.scriptAnswer = JSON.stringify({ version: Date.now() - 700000 });
            staleSource.open();
            tryVerify(() => staleSource.valid);
            compare(freshSource.isFresh(), true);
            compare(staleSource.isFresh(), false);
            // Only the timer for the next cache time runs. A clock timer would wake the engine every minute.
            compare(wakeTimers(freshSource).map(timer => timer.interval > 60000), [true]);
            compare(wakeTimers(staleSource).map(timer => timer.interval > 60000), [true]);
            freshSource.close();
            staleSource.close();
        }

        function test_a_meter_without_a_reading_shows_unknown_and_an_empty_fill() {
            meter.percent = 42;
            meter.timeLeft = "2H 14M";
            const [number, left] = findAll(meter, "value");
            const percentSign = findAll(meter, "text").find(item => item.text === "%");
            tryCompare(number, "text", "42");
            tryCompare(meter, "fillHeight", 84);
            tryCompare(left.parent, "opacity", 1);
            tryCompare(percentSign, "opacity", 1);

            meter.percent = -1;
            meter.timeLeft = "--";
            tryCompare(number, "text", "--");
            tryCompare(meter, "fillHeight", 0);
            tryCompare(left.parent, "opacity", 0);
            tryCompare(percentSign, "opacity", 0);
        }
    }
}
