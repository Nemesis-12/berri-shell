pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "../logic/MemoryUse.js" as MemoryUse
import "../logic/SystemReadings.js" as Readings

/**
 * Live numbers for the System tab. Nothing runs until a SystemTab is
 * visible (`viewers` > 0): FileViews read /proc and /sys each second,
 * `ps` reads processes every 5 s, and `df` reads disks every 30 s.
 * The dGPU is asked only when its runtime power state is "active", so this
 * never wakes it. When it sleeps, the iGPU temperature stands in.
 */
Singleton {
    id: root

    /** How many SystemTab items are visible now. */
    property int viewers: 0
    readonly property bool active: viewers > 0

    // CPU: total percent, per-core percent (SMT threads merged), average GHz, temperature.
    readonly property real cpuPercent: CpuLoad.percent
    readonly property var coreLoads: CpuLoad.coreLoads
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

    /** CPU threads from the same /proc/stat read as the total load. */
    readonly property int threadCount: CpuLoad.threadCount
    property real dgpuTempC: -1

    // Previous network counters for rate calculation.
    property var prevNet: null

    onActiveChanged: {
        if (active) {
            if (!probed) probeProc.running = true;
            else kickAll();
        } else {
            prevNet = null;
        }
    }

    function kickAll() {
        reloadFast();
        if (!processReader.running) processReader.running = true;
        if (!diskReader.running) diskReader.running = true;
        runtimeStatus.reload();
    }

    // Finds sensor paths and static text once.
    Process {
        id: probeProc
        command: ["sh", "-c",
            "for d in /sys/class/hwmon/hwmon*; do echo \"H $(cat $d/name) $d\"; done;"
            + " for d in /sys/bus/pci/devices/*; do case \"$(cat $d/class)\" in 0x03*) [ \"$(cat $d/vendor)\" = 0x10de ] && echo \"D $d\";; esac; done;"
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
                    else if (p[0] === "O") root.distroName = l.slice(2);
                    else if (p[0] === "K") root.kernelName = l.slice(2);
                    else if (p[0] === "N") root.hostName = l.slice(2);
                }
                root.probed = true;
                if (root.active) root.kickAll();
            }
        }
    }

    FileView {
        id: memoryFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: if (root.active) root.readMemory(text())
    }
    FileView {
        id: routeFile
        path: "/proc/net/route"
        printErrors: false
    }
    FileView {
        id: networkFile
        path: "/proc/net/dev"
        printErrors: false
        onLoaded: if (root.active) root.readNetwork()
    }
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        printErrors: false
        onLoaded: if (root.active) {
            var seconds = Readings.readUptime(text());
            if (seconds !== null) root.uptimeSeconds = seconds;
        }
    }
    FileView {
        id: cpuTempFile
        path: root.cpuTempPath
        printErrors: false
        onLoaded: if (root.active) {
            var value = Readings.readSensor(text(), 1000);
            if (value !== null) root.cpuTempC = value;
        }
    }
    FileView {
        id: igpuTempFile
        path: root.igpuTempPath
        printErrors: false
        onLoaded: if (root.active) {
            var value = Readings.readSensor(text(), 1000);
            if (value !== null) {
                root.igpuTempC = value;
                if (root.dgpuTempC < 0) root.gpuTempC = value;
            }
        }
    }
    FileView {
        id: fanFile
        path: root.fanPath
        printErrors: false
        onLoaded: if (root.active) {
            var value = Readings.readSensor(text(), 1);
            if (value !== null) root.fanRpm = value;
        }
    }

    Instantiator {
        id: frequencyFiles
        model: root.threadCount
        delegate: FileView {
            required property int index
            path: "/sys/devices/system/cpu/cpu" + index + "/cpufreq/scaling_cur_freq"
            printErrors: false
            onLoaded: if (root.active) root.readFrequency()
        }
    }

    Process {
        id: processReader
        command: ["ps", "-eo", "pcpu,pmem,comm", "--sort=-pcpu"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.processes = Readings.readProcesses(text, root.threadCount)
        }
    }

    Process {
        id: diskReader
        command: ["df", "-P", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "squashfs"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.readDisks(text)
        }
    }

    FileView {
        id: runtimeStatus
        path: root.dgpuPath ? root.dgpuPath + "/power/runtime_status" : ""
        printErrors: false
        onLoaded: if (root.active) root.readGpuState(text())
        onLoadFailed: if (root.active) root.readGpuState("")
    }

    Process {
        id: gpuReader
        command: ["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var value = Readings.readSensor(text, 1);
                root.dgpuTempC = value === null ? -1 : value;
                root.gpuTempC = value === null ? root.igpuTempC : value;
            }
        }
    }

    Timer {
        interval: 1000
        running: root.active && root.probed
        repeat: true
        onTriggered: root.reloadFast()
    }

    Timer {
        interval: 5000
        running: root.active && root.probed
        repeat: true
        onTriggered: if (!processReader.running) processReader.running = true
    }

    Timer {
        interval: 30000
        running: root.active && root.probed
        repeat: true
        onTriggered: if (!diskReader.running) diskReader.running = true
    }

    Timer {
        interval: 5000
        running: root.active && root.probed && root.dgpuPath !== ""
        repeat: true
        onTriggered: runtimeStatus.reload()
    }

    function readMemory(text) {
        var memory = MemoryUse.readMemoryUse(text);
        if (!memory) return;
        ramTotalGb = memory.totalGb;
        ramUsedGb = memory.usedGb;
        swapTotalGb = memory.swapTotalGb;
        swapUsedGb = memory.swapUsedGb;
    }

    function readNetwork() {
        var next = Readings.readNetwork(routeFile.text(), networkFile.text());
        var now = Date.now();
        netName = next.name;
        if (prevNet && prevNet.name === next.name && next.rx >= 0 && now > prevNet.time) {
            var seconds = (now - prevNet.time) / 1000;
            downMBs = Math.max(0, (next.rx - prevNet.rx) / seconds / 1048576);
            upMBs = Math.max(0, (next.tx - prevNet.tx) / seconds / 1048576);
        }
        if (next.rx >= 0) prevNet = { name: next.name, rx: next.rx, tx: next.tx, time: now };
    }

    function readFrequency() {
        var values = [];
        for (var i = 0; i < frequencyFiles.instances.length; i++)
            values.push(frequencyFiles.instances[i].text());
        var ghz = Readings.readFrequency(values);
        if (ghz !== null) cpuGhz = ghz;
    }

    function reloadFast() {
        memoryFile.reload();
        routeFile.reload();
        networkFile.reload();
        uptimeFile.reload();
        if (cpuTempPath) cpuTempFile.reload();
        if (igpuTempPath) igpuTempFile.reload();
        if (fanPath) fanFile.reload();
        for (var i = 0; i < frequencyFiles.instances.length; i++)
            frequencyFiles.instances[i].reload();
    }

    function readDisks(text) {
        var lines = text.trim().split("\n");
        var seen = {};
        var found = [];
        for (var i = 1; i < lines.length && found.length < 2; i++) {
            var fields = lines[i].trim().split(/\s+/);
            if (fields.length < 6 || seen[fields[0]]) continue;
            var total = Number(fields[1]) / 1048576;
            if (total < 20) continue;
            seen[fields[0]] = true;
            found.push({ mount: fields[5], device: fields[0].split("/").pop(),
                usedGb: Number(fields[2]) / 1048576, totalGb: total });
        }
        disks = found;
    }

    function readGpuState(text) {
        if (text.trim() === "active") {
            if (!gpuReader.running) gpuReader.running = true;
        } else {
            dgpuTempC = -1;
            gpuTempC = igpuTempC;
        }
    }
}
