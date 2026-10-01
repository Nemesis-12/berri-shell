pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/MemoryUse.js" as MemoryUse

/**
 * Live numbers for the System tab. Nothing runs until a SystemTab is
 * visible (`viewers` > 0): then one small process reads /proc and /sys every
 * second, one runs `top` every 3 s for the process list, and one runs `df`
 * plus the dGPU temperature every 5 s. When the tab hides, all timers stop.
 * The dGPU is asked only when its runtime power state is "active", so this
 * never wakes it. When it sleeps, the iGPU temperature stands in.
 */
Singleton {
    id: root

    /** How many SystemTab items are visible now. */
    property int viewers: 0
    readonly property bool active: viewers > 0

    // CPU: total percent, per-core percent (SMT threads merged), average GHz, temperature.
    property real cpuPercent: 0
    property var coreLoads: [0, 0, 0, 0, 0, 0, 0, 0]
    property real cpuGhz: 0
    property real cpuTempC: 0

    // Sensors. gpuTempC is the dGPU when awake, else the iGPU.
    property real gpuTempC: 0
    property int fanRpm: 0

    // Memory in GiB.
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property real swapUsedGb: 0
    property real swapTotalGb: 0

    // Network: default-route interface, MB/s.
    property string netName: ""
    property real downMBs: 0
    property real upMBs: 0

    /** [{ mount, device, usedGb, totalGb }] for up to two big disks. */
    property var disks: []

    /** [{ name, cpu, mem }] up to 8 rows, busiest first. */
    property var processes: []

    property string hostName: ""
    property string kernelName: ""
    property string distroName: ""
    property real uptimeSeconds: 0

    // Sensor file paths, found once by the probe.
    property string cpuTempPath: ""
    property string igpuTempPath: ""
    property string fanPath: ""
    property string dgpuPath: ""
    property bool probed: false

    /** CPU threads, read once by the probe. `top` counts one busy thread as 100%, so its values are divided by this. */
    property int threadCount: 1
    property real dgpuTempC: -1

    // Previous counters for the delta maths.
    property var prevCpu: null
    property var prevNet: null

    onActiveChanged: {
        if (active) {
            if (!probed) probeProc.running = true;
            else kickAll();
        } else {
            prevCpu = null;
            prevNet = null;
        }
    }

    function kickAll() {
        if (!fastProc.running) fastProc.running = true;
        if (!topProc.running) topProc.running = true;
        if (!slowProc.running) slowProc.running = true;
    }

    // Finds sensor paths, disk-free identity and static text once.
    Process {
        id: probeProc
        command: ["sh", "-c",
            "for d in /sys/class/hwmon/hwmon*; do echo \"H $(cat $d/name) $d\"; done;"
            + " for d in /sys/bus/pci/devices/*; do case \"$(cat $d/class)\" in 0x03*) [ \"$(cat $d/vendor)\" = 0x10de ] && echo \"D $d\";; esac; done;"
            + " echo \"T $(getconf _NPROCESSORS_ONLN)\";"
            + " echo \"O $(. /etc/os-release; echo $NAME)\"; echo \"K $(cat /proc/sys/kernel/osrelease)\"; echo \"N $(cat /proc/sys/kernel/hostname)\""]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines = text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i];
                    var p = l.split(" ");
                    if (p[0] === "H") {
                        if (p[1] === "k10temp") root.cpuTempPath = p[2] + "/temp1_input";
                        else if (p[1] === "amdgpu") root.igpuTempPath = p[2] + "/temp1_input";
                        else if (p[1] === "asus") root.fanPath = p[2] + "/fan1_input";
                    } else if (p[0] === "D") root.dgpuPath = p[1];
                    else if (p[0] === "T") root.threadCount = Math.max(1, Number(p[1]) || 1);
                    else if (p[0] === "O") root.distroName = l.slice(2);
                    else if (p[0] === "K") root.kernelName = l.slice(2);
                    else if (p[0] === "N") root.hostName = l.slice(2);
                }
                root.probed = true;
                if (root.active) root.kickAll();
            }
        }
    }

    Process {
        id: fastProc
        command: {
            var files = [root.cpuTempPath, root.igpuTempPath, root.fanPath].filter(function (f) { return f !== ""; });
            return ["sh", "-c",
                "awk 'FNR==1{print \"@@\" FILENAME} {print}' /proc/stat /proc/meminfo /proc/net/dev /proc/net/route /proc/uptime"
                + " /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq \"$@\" 2>/dev/null", "sh"].concat(files);
        }
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.onFast(text)
        }
    }

    Process {
        id: topProc
        command: ["sh", "-c",
            "top -b -n 2 -d 1 -w 256 -o %CPU | awk '"
            + "/^top -/{f++} f==2 && /PID/ && /%CPU/{for(i=1;i<=NF;i++){if($i==\"%CPU\")c=i; if($i==\"%MEM\")m=i; if($i==\"COMMAND\")k=i}; on=1; next}"
            + " f==2 && on && $1+0>0{n=$k; for(i=k+1;i<=NF;i++)n=n\" \"$i; if(n==\"top\"||n==\"awk\"||n==\"sh\")next; cpu[n]+=$c; mem[n]+=$m}"
            + " END{for(n in cpu) printf \"%.1f\\t%.1f\\t%s\\n\", cpu[n], mem[n], n | \"sort -k1,1nr | head -n 8\"}'"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.onTop(text)
        }
    }

    Process {
        id: slowProc
        command: ["sh", "-c",
            "df -P -x tmpfs -x devtmpfs -x efivarfs -x squashfs; echo @@GPU;"
            + " if [ -n \"$1\" ] && [ \"$(cat $1/power/runtime_status)\" = active ]; then"
            + " nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits; fi", "sh", root.dgpuPath]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.onSlow(text)
        }
    }

    Timer {
        interval: 1000
        running: root.active && root.probed
        repeat: true
        onTriggered: if (!fastProc.running) fastProc.running = true
    }

    Timer {
        interval: 3000
        running: root.active && root.probed
        repeat: true
        onTriggered: if (!topProc.running) topProc.running = true
    }

    Timer {
        interval: 5000
        running: root.active && root.probed
        repeat: true
        onTriggered: if (!slowProc.running) slowProc.running = true
    }

    /** Splits the awk dump into { path: [lines] }. */
    function sections(text) {
        var out = {};
        var parts = text.split("@@");
        for (var i = 1; i < parts.length; i++) {
            var nl = parts[i].indexOf("\n");
            out[parts[i].slice(0, nl)] = parts[i].slice(nl + 1).split("\n");
        }
        return out;
    }

    function onFast(text) {
        var s = sections(text);
        var now = Date.now();

        // CPU: threads i and i + n/2 share a core (checked on this laptop).
        var stat = s["/proc/stat"] || [];
        var cur = [];
        for (var i = 0; i < stat.length; i++) {
            if (stat[i].indexOf("cpu") !== 0) continue;
            var f = stat[i].trim().split(/\s+/).slice(1).map(Number);
            var total = f.reduce(function (a, b) { return a + b; }, 0);
            cur.push({ idle: f[3] + (f[4] || 0), total: total });
        }
        if (prevCpu && prevCpu.length === cur.length) {
            var pct = function (a, b) {
                var dt = a.total - b.total;
                return dt > 0 ? Math.max(0, Math.min(100, 100 * (dt - (a.idle - b.idle)) / dt)) : 0;
            };
            cpuPercent = pct(cur[0], prevCpu[0]);
            var threads = cur.length - 1;
            var cores = threads >= 16 ? threads / 2 : threads;
            var loads = [];
            for (var c = 0; c < Math.min(8, cores); c++) {
                if (threads >= 16) loads.push((pct(cur[1 + c], prevCpu[1 + c]) + pct(cur[1 + c + cores], prevCpu[1 + c + cores])) / 2);
                else loads.push(pct(cur[1 + c], prevCpu[1 + c]));
            }
            coreLoads = loads;
        }
        prevCpu = cur;

        // Memory.
        var memory = MemoryUse.readMemoryUse((s["/proc/meminfo"] || []).join("\n"));
        if (memory) {
            ramTotalGb = memory.totalGb;
            ramUsedGb = memory.usedGb;
            swapTotalGb = memory.swapTotalGb;
            swapUsedGb = memory.swapUsedGb;
        }

        // Network: default-route interface (else the first non-loopback one).
        var route = s["/proc/net/route"] || [];
        var iface = "";
        for (var r = 1; r < route.length; r++) {
            var rf = route[r].split(/\s+/);
            if (rf[1] === "00000000") { iface = rf[0]; break; }
        }
        var dev = s["/proc/net/dev"] || [];
        var rx = -1, tx = -1;
        for (var d = 2; d < dev.length; d++) {
            var colon = dev[d].indexOf(":");
            if (colon < 0) continue;
            var name = dev[d].slice(0, colon).trim();
            if (iface === "" && name !== "lo") iface = name;
            if (name === iface) {
                var nf = dev[d].slice(colon + 1).trim().split(/\s+/).map(Number);
                rx = nf[0];
                tx = nf[8];
            }
        }
        netName = iface;
        if (prevNet && prevNet.iface === iface && rx >= 0 && now > prevNet.t) {
            var dts = (now - prevNet.t) / 1000;
            downMBs = Math.max(0, (rx - prevNet.rx) / dts / 1048576);
            upMBs = Math.max(0, (tx - prevNet.tx) / dts / 1048576);
        }
        prevNet = { iface: iface, rx: rx, tx: tx, t: now };

        // Frequency, temperatures, fan, uptime.
        var sum = 0, count = 0;
        for (var key in s) {
            if (key.indexOf("scaling_cur_freq") > 0) {
                sum += Number(s[key][0]);
                count++;
            }
        }
        if (count > 0) cpuGhz = sum / count / 1e6;
        if (s[cpuTempPath]) cpuTempC = Number(s[cpuTempPath][0]) / 1000;
        if (s[fanPath]) fanRpm = Number(s[fanPath][0]);
        // iGPU stands in until the slow sample says the dGPU is awake.
        if (s[igpuTempPath] && dgpuTempC < 0) gpuTempC = Number(s[igpuTempPath][0]) / 1000;
        else if (s[igpuTempPath]) igpuTempC = Number(s[igpuTempPath][0]) / 1000;
        if (s["/proc/uptime"]) uptimeSeconds = Number(s["/proc/uptime"][0].split(" ")[0]);
    }

    property real igpuTempC: 0

    function onTop(text) {
        var rows = [];
        var lines = text.trim().split("\n");
        for (var i = 0; i < lines.length; i++) {
            var f = lines[i].split("\t");
            if (f.length < 3) continue;
            // Share of the whole CPU, on the same scale as cpuPercent.
            rows.push({ cpu: Number(f[0]) / threadCount, mem: Number(f[1]), name: f[2] });
        }
        processes = rows;
    }

    function onSlow(text) {
        var parts = text.split("@@GPU\n");
        var lines = parts[0].trim().split("\n");
        var seen = {};
        var found = [];
        for (var i = 1; i < lines.length && found.length < 2; i++) {
            var f = lines[i].trim().split(/\s+/);
            if (f.length < 6 || seen[f[0]]) continue;
            var total = Number(f[1]) / 1048576;
            if (total < 20) continue;
            seen[f[0]] = true;
            found.push({
                mount: f[5],
                device: f[0].split("/").pop(),
                usedGb: Number(f[2]) / 1048576,
                totalGb: total
            });
        }
        disks = found;

        var temp = parseFloat((parts[1] || "").trim());
        dgpuTempC = isNaN(temp) ? -1 : temp;
        if (dgpuTempC >= 0) gpuTempC = dgpuTempC;
        else if (igpuTempC > 0) gpuTempC = igpuTempC;
    }
}
