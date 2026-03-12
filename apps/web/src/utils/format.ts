import { formatUnits } from "@/utils/amount";

export function shortenAddress(address: string, visibleCharacters = 4): string {
  if (address.length <= visibleCharacters * 2 + 2) {
    return address;
  }

  return `${address.slice(0, visibleCharacters + 2)}...${address.slice(-visibleCharacters)}`;
}

export function formatTimestamp(unixTimestampSeconds: number): string {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(unixTimestampSeconds * 1000));
}

export function formatDuration(durationSeconds: number): string {
  if (durationSeconds < 60) {
    return `${durationSeconds}s`;
  }

  if (durationSeconds < 3600) {
    const minutes = Math.floor(durationSeconds / 60);
    const seconds = durationSeconds % 60;
    return seconds > 0 ? `${minutes}m ${seconds}s` : `${minutes}m`;
  }

  const hours = Math.floor(durationSeconds / 3600);
  const minutes = Math.floor((durationSeconds % 3600) / 60);
  return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
}

export function formatSignedUnits(value: bigint, decimals: number, precision = 4): string {
  if (value === 0n) {
    return "0";
  }

  const absoluteValue = value < 0n ? value * -1n : value;
  const sign = value > 0n ? "+" : "-";
  return `${sign}${formatUnits(absoluteValue, decimals, precision)}`;
}

export function formatAttestationLabel(attestationCount: number): string {
  if (attestationCount === 1) {
    return "1 validator";
  }

  return `${attestationCount} validators`;
}
