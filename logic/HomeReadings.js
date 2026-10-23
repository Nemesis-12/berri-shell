.pragma library

/** True when UPower has a battery that this Home cell can show. */
function hasBattery(device) {
    return Boolean(device && device.ready && device.isLaptopBattery && device.isPresent);
}
