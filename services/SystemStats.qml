pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/SystemReadings.js" as Readings

/**
 * Live numbers for the System tab. Nothing runs until a SystemTab is
 * visible (`viewers` > 0). Sensors, frequency and network refresh each second.
 * Processes refresh every 5 s. SystemUsage supplies memory, disks and uptime.
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
    readonly property int threadCount: CpuLoad.threadCount
    property var cpuGhz: null
    property var cpuTempC: null

    // Sensors. gpuTempC is the dGPU when awake, else the iGPU.
    property var gpuTempC: null
    property var igpuTempC: null
    property var fanRpm: null

    // Memory in GiB.
    readonly property real ramUsedGb: SystemUsage.ramUsedGb
    readonly property real ramTotalGb: SystemUsage.ramTotalGb
    readonly property real swapUsedGb: SystemUsage.swapUsedGb
    readonly property real swapTotalGb: SystemUsage.swapTotalGb

    // Network: default-route interface, MB/s.
    property string netName: ""
    property real downMBs: 0
    property real upMBs: 0

    /** [{ mount, device, usedGb, totalGb }] for up to two big disks. */
    readonly property var disks: SystemUsage.disks.filter(function (disk) {
        return disk.mount === "/" || disk.totalGb >= 20;
    }).slice(0, 2)

    /** [{ name, cpu, mem }] up to 8 rows, busiest first. */
    property var processes: []

    property string hostName: ""
    property string kernelName: ""
    property string distroName: ""
    readonly property real uptimeSeconds: SystemUsage.uptimeSeconds

    // Sensor file paths, found once by the probe.
    property string cpuTempPath: ""
    property string igpuTempPath: ""
    property string fanPath: ""
    property string dgpuPath: ""
    property bool probed: false

    property var dgpuTempC: null
    property var sensorWarnings: ({})

    // Previous network counters for rate calculation.
    property var prevNet: null
    property var prevProcessSample: null

    onActiveChanged: {
        if (active) {
            SystemUsage.viewers++;
            kickAll();
            if (!probed && !probeProc.running) probeProc.running = true;
        } else {
            SystemUsage.viewers--;
            frequencyReader.running = false;
            processReader.running = false;
            gpuReader.running = false;
            prevNet = null;
            prevProcessSample = null;
            processes = [];
        }
    }

    // Starts the first process and fast samples as soon as the tab opens.
    function kickAll() {
        if (!processReader.running) processReader.running = true;
        reloadFast();
        runtimeStatus.reload();
    }

    // Finds sensor paths and static text once.
    Process {
        id: probeProc
        command: ["sh", "-c", "sh \"$1\" sensors;"
            + " echo \"O $(. /etc/os-release; echo $NAME)\"; echo \"K $(cat /proc/sys/kernel/osrelease)\"; echo \"N $(cat /proc/sys/kernel/hostname)\"",
            "system-probe", Quickshell.shellPath("scripts/system-hardware.sh")]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.readProbe(text)
        }
    }

    // Publishes available sensor paths and reports missing sensors once.
    function readProbe(text) {
        var sensors = Readings.readSensors(text);
        cpuTempPath = sensors.cpuTempPath;
        igpuTempPath = sensors.igpuTempPath;
        fanPath = sensors.fanPath;
        dgpuPath = sensors.dgpuPath;
        sensors.missing.forEach(function (name) { root.sensorUnavailable(name); });
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("O ") === 0) distroName = lines[i].slice(2);
            else if (lines[i].indexOf("K ") === 0) kernelName = lines[i].slice(2);
            else if (lines[i].indexOf("N ") === 0) hostName = lines[i].slice(2);
        }
        probed = true;
    }

    // A missing sensor or a failed read produces only one warning per session.
    function sensorUnavailable(name) {
        if (sensorWarnings[name]) return;
        sensorWarnings[name] = true;
        console.warn("SystemStats: " + name + " sensor is unavailable");
    }

    // Clears failed sensor readings instead of retaining a stale or false value.
    function readSensorSample(name, text, divisor) {
        var value = Readings.readSensor(text, divisor);
        if (name === "CPU temperature") cpuTempC = value;
        else if (name === "GPU temperature") {
            igpuTempC = value;
            if (dgpuTempC === null) gpuTempC = value;
        } else fanRpm = value;
        if (value === null) sensorUnavailable(name);
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
        id: cpuTempFile
        path: root.cpuTempPath
        printErrors: false
        onLoaded: if (root.active) root.readSensorSample("CPU temperature", text(), 1000)
        onLoadFailed: if (root.active && root.cpuTempPath) root.readSensorSample("CPU temperature", "", 1000)
    }

    FileView {
        id: igpuTempFile
        path: root.igpuTempPath
        printErrors: false
        onLoaded: if (root.active) root.readSensorSample("GPU temperature", text(), 1000)
        onLoadFailed: if (root.active && root.igpuTempPath) root.readSensorSample("GPU temperature", "", 1000)
    }

    FileView {
        id: fanFile
        path: root.fanPath
        printErrors: false
        onLoaded: if (root.active) root.readSensorSample("fan speed", text(), 1)
        onLoadFailed: if (root.active && root.fanPath) root.readSensorSample("fan speed", "", 1)
    }

    Process {
        id: frequencyReader
        command: ["sh", Quickshell.shellPath("scripts/system-hardware.sh"), "frequency"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (root.active) root.readFrequency(text)
        }
    }

    Process {
        id: processReader
        command: ["sh", "-c",
            "IFS= read -r cpu < /proc/stat; printf '%s\n' \"$cpu\"; "
            + "ps -eo pid=,pmem=,comm= | while read -r pid mem name; do "
            + "IFS= read -r stat 2>/dev/null < \"/proc/$pid/stat\" || continue; "
            + "printf '%s\t%s\t%s\t%s\n' \"$pid\" \"$mem\" \"$name\" \"$stat\"; done"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (!root.active) return;
                var result = Readings.readProcesses(text, root.prevProcessSample);
                root.prevProcessSample = result.sample;
                root.processes = result.rows;
            }
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
                if (!root.active) return;
                var value = Readings.readSensor(text, 1);
                root.dgpuTempC = value;
                if (value === null) root.sensorUnavailable("GPU temperature");
                root.gpuTempC = value === null ? root.igpuTempC : value;
            }
        }
    }

    Timer {
        interval: 1000
        running: root.active
        repeat: true
        onTriggered: root.reloadFast()
    }

    Timer {
        interval: 5000
        running: root.active
        repeat: true
        onTriggered: if (!processReader.running) processReader.running = true
    }

    Timer {
        interval: 5000
        running: root.active && root.dgpuPath !== ""
        repeat: true
        onTriggered: runtimeStatus.reload()
    }

    // Derives transfer rates from consecutive byte counters for the same interface.
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

    // Called once after all thread frequency files have been read.
    function readFrequency(text) {
        var ghz = Readings.readFrequency(text.split("\n"));
        cpuGhz = ghz;
        if (ghz === null) sensorUnavailable("CPU frequency");
    }

    // Starts one completed frequency sample and refreshes available sensors.
    function reloadFast() {
        routeFile.reload();
        networkFile.reload();
        if (cpuTempPath) cpuTempFile.reload();
        if (igpuTempPath) igpuTempFile.reload();
        if (fanPath) fanFile.reload();
        if (!frequencyReader.running) frequencyReader.running = true;
    }

    // Queries NVIDIA only while its runtime power state is active.
    function readGpuState(text) {
        if (text.trim() === "active") {
            if (!gpuReader.running) gpuReader.running = true;
        } else {
            dgpuTempC = null;
            gpuTempC = igpuTempC;
        }
    }
}
