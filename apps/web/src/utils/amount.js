export function parseUnits(value, decimals) {
    const sanitized = value.trim();
    if (!sanitized)
        return 0n;
    if (!/^\d*(\.\d*)?$/.test(sanitized)) {
        throw new Error("invalid decimal amount");
    }
    const [whole = "0", fraction = ""] = sanitized.split(".");
    const fractionPadded = (fraction + "0".repeat(decimals)).slice(0, decimals);
    const full = `${whole}${fractionPadded}`.replace(/^0+(?=\d)/, "");
    return BigInt(full || "0");
}
export function formatUnits(value, decimals, precision = 6) {
    const divisor = 10n ** BigInt(decimals);
    const whole = value / divisor;
    const fraction = value % divisor;
    const fractionRaw = fraction.toString().padStart(decimals, "0").slice(0, precision);
    const trimmed = fractionRaw.replace(/0+$/, "");
    return trimmed ? `${whole}.${trimmed}` : whole.toString();
}
