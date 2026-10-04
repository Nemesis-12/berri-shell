#!/bin/sh
# Reads Linux hardware files. The optional sysfs root is for isolated tests.

system_root=${2:-/sys}
case "$1" in
    cores|frequency)
        for cpu in "$system_root"/devices/system/cpu/cpu[0-9]*; do
            [ -d "$cpu" ] || continue
            if [ -f "$cpu/online" ]; then
                IFS= read -r online < "$cpu/online" || continue
                [ "$online" = 1 ] || continue
            fi
            if [ "$1" = cores ]; then
                [ -r "$cpu/topology/physical_package_id" ] && [ -r "$cpu/topology/core_id" ] || continue
                IFS= read -r package < "$cpu/topology/physical_package_id" || continue
                IFS= read -r core < "$cpu/topology/core_id" || continue
                number=${cpu##*/cpu}
                printf '%s %s %s\n' "$number" "$package" "$core"
            else
                [ -r "$cpu/cpufreq/scaling_cur_freq" ] || continue
                IFS= read -r frequency < "$cpu/cpufreq/scaling_cur_freq" || continue
                printf '%s\n' "$frequency"
            fi
        done
        ;;
    sensors)
        for sensor in "$system_root"/class/hwmon/hwmon*; do
            [ -r "$sensor/name" ] || continue
            IFS= read -r name < "$sensor/name" || continue
            for input in "$sensor"/temp*_input "$sensor"/fan*_input; do
                [ -r "$input" ] || continue
                label=
                if [ -r "${input%_input}_label" ]; then
                    IFS= read -r label < "${input%_input}_label"
                fi
                printf 'S\t%s\t%s\t%s\n' "$name" "$input" "$label"
            done
        done
        for device in "$system_root"/bus/pci/devices/*; do
            [ -r "$device/class" ] && [ -r "$device/vendor" ] || continue
            IFS= read -r class < "$device/class" || continue
            IFS= read -r vendor < "$device/vendor" || continue
            case "$class:$vendor" in 0x03*:0x10de) printf 'D\t%s\n' "$device";; esac
        done
        ;;
    *) exit 2 ;;
esac
exit 0
