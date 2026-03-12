import { chainLabel } from "@/config/networks";
import { SUPPORTED_TOKENS } from "@/config/tokens";
import { isBridgeTransferClaimable } from "@/services/bridge";
import type {
  IndexedAttestation,
  IndexedClaim,
  IndexedDeposit,
  TransferDashboardResponse,
  TransferRecord,
  TransferState,
} from "@/types/transfers";

interface FetchTransferRecordsOptions {
  limit?: number;
  claimLimit?: number;
  attestationLimit?: number;
  graphqlUrl?: string;
  includeRuntimeState?: boolean;
}

interface GraphqlResponse<TData> {
  data?: TData;
  errors?: Array<{ message: string }>;
}

interface ResolvedAssetMetadata {
  assetSymbol: string;
  assetName: string;
  assetDecimals: number;
}

interface RuntimeTransferState {
  claimable: boolean;
  sourceStateRoot: `0x${string}` | null;
}

const DEFAULT_GRAPHQL_URL =
  import.meta.env.VITE_HASURA_URL ??
  import.meta.env.VITE_INDEXER_GRAPHQL_URL ??
  "http://localhost:8180/v1/graphql";
const NATIVE_TOKEN_ADDRESS = "0x0000000000000000000000000000000000000000";

const TRANSFER_DASHBOARD_QUERY = `
  query TransferDashboard($wallet: String!, $depositLimit: Int!, $claimLimit: Int!, $attestationLimit: Int!) {
    Deposit(
      limit: $depositLimit,
      order_by: { timestamp: desc },
      where: { _or: [{ user_id: { _eq: $wallet } }, { to: { _eq: $wallet } }] }
    ) {
      id
      user_id
      token_id
      to
      amount
      sourceChain
      destinationChain
      blockNumber
      depositIndex
      depositRoot
      transactionHash
      timestamp
    }
    Claim(
      limit: $claimLimit,
      order_by: { timestamp: desc },
      where: { _or: [{ user_id: { _eq: $wallet } }, { to: { _eq: $wallet } }] }
    ) {
      id
      user_id
      amount
      token_id
      to
      sourceChain
      destinationChain
      transactionHash
      timestamp
      deposit_id
    }
    Attestation(limit: $attestationLimit, order_by: { blockTimestamp: desc }) {
      id
      validator
      sourceChainId
      sourceBlockNumber
      bridgeRoot
      blockTimestamp
    }
  }
`;

function normalizeAddress(value: string): string {
  return value.toLowerCase();
}

function isNativeTokenAddress(value: string): boolean {
  return normalizeAddress(value) === NATIVE_TOKEN_ADDRESS;
}

function depositClaimKey(deposit: IndexedDeposit): string {
  return `${deposit.sourceChain}-${deposit.depositIndex}`;
}

function attestationKey(
  sourceChainId: string,
  sourceBlockNumber: string,
  bridgeRoot: string,
): string {
  return `${sourceChainId}:${sourceBlockNumber}:${bridgeRoot.toLowerCase()}`;
}

function runtimeStateKey(
  record: Pick<
    TransferRecord,
    "destinationChainId" | "sourceBlockNumber" | "sourceChainId" | "sourceRoot"
  >,
): string {
  return `${record.destinationChainId}:${record.sourceChainId}:${record.sourceBlockNumber}:${record.sourceRoot.toLowerCase()}`;
}

function resolveAssetMetadata(deposit: IndexedDeposit): ResolvedAssetMetadata {
  if (isNativeTokenAddress(deposit.token_id)) {
    return {
      assetSymbol: "ETH",
      assetName: "Ether",
      assetDecimals: 18,
    };
  }

  const matchedToken = SUPPORTED_TOKENS.find(
    (token) =>
      token.chainId === Number(deposit.sourceChain) &&
      token.address.toLowerCase() === deposit.token_id.toLowerCase(),
  );

  if (matchedToken) {
    return {
      assetSymbol: matchedToken.symbol,
      assetName: matchedToken.name,
      assetDecimals: matchedToken.decimals,
    };
  }

  return {
    assetSymbol: "TOKEN",
    assetName: deposit.token_id,
    assetDecimals: 18,
  };
}

function resolveTransferState(
  attestationCount: number,
  hasClaim: boolean,
  claimable: boolean,
): TransferState {
  if (hasClaim) {
    return "complete";
  }

  if (claimable) {
    return "claimable";
  }

  if (attestationCount > 0) {
    return "attesting";
  }

  return "pending";
}

function resolveStateLabels(
  state: TransferState,
  attestationCount: number,
  destinationChainId: number,
): { stateLabel: string; detailLabel: string } {
  if (state === "complete") {
    return {
      stateLabel: "Received",
      detailLabel: `Money arrived on ${chainLabel(destinationChainId)}`,
    };
  }

  if (state === "claimable") {
    return {
      stateLabel: "Ready to receive",
      detailLabel: `Open ${chainLabel(destinationChainId)} and finish the transfer`,
    };
  }

  if (state === "attesting") {
    return {
      stateLabel: "Checks running",
      detailLabel:
        attestationCount === 1
          ? "1 security check is complete"
          : `${attestationCount} security checks are complete`,
    };
  }

  return {
    stateLabel: "Starting",
    detailLabel: "Transfer recorded and waiting for security checks",
  };
}

export function buildTransferRecords(
  walletAddress: string,
  deposits: IndexedDeposit[],
  claims: IndexedClaim[],
  attestations: IndexedAttestation[],
  currentTimestampSeconds = Math.floor(Date.now() / 1000),
): TransferRecord[] {
  const normalizedWallet = normalizeAddress(walletAddress);
  const claimsByDepositId = new Map<string, IndexedClaim>();
  const attestationCountsByKey = new Map<string, Set<string>>();

  for (const claim of claims) {
    if (!claim.deposit_id || claimsByDepositId.has(claim.deposit_id)) {
      continue;
    }

    claimsByDepositId.set(claim.deposit_id, claim);
  }

  for (const attestation of attestations) {
    const key = attestationKey(
      attestation.sourceChainId,
      attestation.sourceBlockNumber,
      attestation.bridgeRoot,
    );
    const validatorSet = attestationCountsByKey.get(key) ?? new Set<string>();
    validatorSet.add(attestation.validator.toLowerCase());
    attestationCountsByKey.set(key, validatorSet);
  }

  return deposits
    .filter((deposit) => {
      const depositorMatches = normalizeAddress(deposit.user_id) === normalizedWallet;
      const recipientMatches = normalizeAddress(deposit.to) === normalizedWallet;
      return depositorMatches || recipientMatches;
    })
    .map((deposit) => {
      const sourceChainId = Number(deposit.sourceChain);
      const destinationChainId = Number(deposit.destinationChain ?? deposit.sourceChain);
      const matchingClaim = claimsByDepositId.get(depositClaimKey(deposit));
      const uniqueAttestationCount =
        attestationCountsByKey.get(
          attestationKey(deposit.sourceChain, deposit.blockNumber, deposit.depositRoot),
        )?.size ?? 0;
      const depositTimestamp = Number(deposit.timestamp);
      const claimTimestamp = matchingClaim ? Number(matchingClaim.timestamp) : null;
      const durationSeconds = Math.max(
        0,
        (claimTimestamp ?? currentTimestampSeconds) - depositTimestamp,
      );
      const sender = normalizeAddress(deposit.user_id);
      const recipient = normalizeAddress(deposit.to);
      const walletIsSender = sender === normalizedWallet;
      const walletIsRecipient = recipient === normalizedWallet;
      const state = resolveTransferState(
        uniqueAttestationCount,
        Boolean(matchingClaim),
        false,
      );
      const { stateLabel, detailLabel } = resolveStateLabels(
        state,
        uniqueAttestationCount,
        destinationChainId,
      );
      const { assetSymbol, assetName, assetDecimals } = resolveAssetMetadata(deposit);

      return {
        id: deposit.id,
        sourceChainId,
        destinationChainId,
        sourceBlockNumber: Number(deposit.blockNumber),
        depositIndex: Number(deposit.depositIndex),
        sourceRoot: deposit.depositRoot as `0x${string}`,
        sourceStateRoot: null,
        sourceTokenAddress: deposit.token_id as `0x${string}`,
        sourceChainLabel: chainLabel(sourceChainId),
        destinationChainLabel: chainLabel(destinationChainId),
        assetSymbol,
        assetName,
        assetDecimals,
        amount: BigInt(deposit.amount),
        depositTimestamp,
        claimTimestamp,
        durationSeconds,
        attestationCount: uniqueAttestationCount,
        state,
        stateLabel,
        detailLabel,
        depositTransactionHash: deposit.transactionHash,
        claimTransactionHash: matchingClaim?.transactionHash ?? null,
        sender,
        recipient,
        walletIsSender,
        walletIsRecipient,
      } satisfies TransferRecord;
    })
    .sort((left, right) => right.depositTimestamp - left.depositTimestamp);
}

export function applyTransferRuntimeState(
  records: TransferRecord[],
  runtimeStateByKey: Map<string, RuntimeTransferState>,
): TransferRecord[] {
  return records.map((record) => {
    const runtimeState = runtimeStateByKey.get(runtimeStateKey(record));
    const state = resolveTransferState(
      record.attestationCount,
      Boolean(record.claimTransactionHash),
      runtimeState?.claimable ?? false,
    );
    const { stateLabel, detailLabel } = resolveStateLabels(
      state,
      record.attestationCount,
      record.destinationChainId,
    );

    return {
      ...record,
      sourceStateRoot: runtimeState?.sourceStateRoot ?? record.sourceStateRoot,
      state,
      stateLabel,
      detailLabel,
    };
  });
}

export function markTransferRecordReceived(
  record: TransferRecord,
  claimTimestampSeconds: number,
  claimTransactionHash: string | null,
): TransferRecord {
  const { stateLabel, detailLabel } = resolveStateLabels(
    "complete",
    record.attestationCount,
    record.destinationChainId,
  );

  return {
    ...record,
    claimTimestamp: claimTimestampSeconds,
    claimTransactionHash,
    durationSeconds: Math.max(0, claimTimestampSeconds - record.depositTimestamp),
    state: "complete",
    stateLabel,
    detailLabel,
  };
}

async function resolveTransferRuntimeState(
  records: TransferRecord[],
): Promise<Map<string, RuntimeTransferState>> {
  const runtimeStateByKey = new Map<string, RuntimeTransferState>();
  const checkableRecords = records.filter(
    (record) => record.claimTransactionHash === null && record.attestationCount > 0,
  );
  const uniqueRecords = Array.from(
    new Map(checkableRecords.map((record) => [runtimeStateKey(record), record])).values(),
  );

  await Promise.all(
    uniqueRecords.map(async (record) => {
      try {
        const result = await isBridgeTransferClaimable(record);
        runtimeStateByKey.set(runtimeStateKey(record), {
          claimable: result.claimable,
          sourceStateRoot: result.stateRoot,
        });
      } catch {
        runtimeStateByKey.set(runtimeStateKey(record), {
          claimable: false,
          sourceStateRoot: null,
        });
      }
    }),
  );

  return runtimeStateByKey;
}

export async function fetchTransferRecords(
  walletAddress: string,
  options: FetchTransferRecordsOptions = {},
): Promise<TransferRecord[]> {
  const response = await fetch(options.graphqlUrl ?? DEFAULT_GRAPHQL_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify({
      query: TRANSFER_DASHBOARD_QUERY,
      variables: {
        wallet: walletAddress,
        depositLimit: options.limit ?? 40,
        claimLimit: options.claimLimit ?? options.limit ?? 40,
        attestationLimit: options.attestationLimit ?? 250,
      },
    }),
  });

  if (!response.ok) {
    throw new Error(`Indexer request failed with status ${response.status}`);
  }

  const payload = (await response.json()) as GraphqlResponse<TransferDashboardResponse>;

  if (payload.errors && payload.errors.length > 0) {
    throw new Error(payload.errors.map((error) => error.message).join("; "));
  }

  if (!payload.data) {
    throw new Error("Indexer returned no data");
  }

  const records = buildTransferRecords(
    walletAddress,
    payload.data.Deposit,
    payload.data.Claim,
    payload.data.Attestation,
  );
  if (options.includeRuntimeState === false) {
    return records;
  }

  const runtimeStateByKey = await resolveTransferRuntimeState(records);
  return applyTransferRuntimeState(records, runtimeStateByKey);
}
