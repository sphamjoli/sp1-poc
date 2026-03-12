const ZERO_B256 = `0x${"0".repeat(64)}`;

function asString(value: unknown, fallback: string): string {
  if (typeof value === "string") return value;
  if (
    typeof value === "number" ||
    typeof value === "bigint" ||
    typeof value === "boolean"
  ) {
    return String(value);
  }
  return fallback;
}

function asBigInt(value: unknown, fallback: bigint): bigint {
  if (typeof value === "bigint") return value;
  if (typeof value === "number" && Number.isFinite(value)) return BigInt(Math.trunc(value));
  if (typeof value === "string" && value.trim() !== "") {
    try {
      return BigInt(value);
    } catch {
      return fallback;
    }
  }
  if (typeof value === "boolean") return value ? 1n : 0n;
  return fallback;
}

export function resolveClaimClaimer(params: Record<string, unknown>): string {
  return asString(params.claimer ?? params.who, "");
}

export function resolveClaimRecipient(
  params: Record<string, unknown>,
  fallback: string,
): string {
  return asString(params.recipient ?? params.to, fallback);
}

export function resolveSourceChainId(params: Record<string, unknown>): bigint {
  return asBigInt(params.sourceChainId, 0n);
}

export function resolveSourceBlockNumber(params: Record<string, unknown>): bigint {
  return asBigInt(params.blockNumber ?? params.sourceBlockNumber, 0n);
}

export function resolveStateRoot(params: Record<string, unknown>): string {
  return asString(params.stateRoot, ZERO_B256);
}

export function resolveEventSourceAddress(
  event: Record<string, unknown>,
  fallback: string,
): string {
  return asString(event.srcAddress, fallback);
}

export function resolveAttestationTimestamp(
  params: Record<string, unknown>,
  fallback: bigint,
): bigint {
  return asBigInt(params.timestamp, fallback);
}
