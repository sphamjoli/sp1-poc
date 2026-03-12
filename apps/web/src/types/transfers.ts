export interface IndexedDeposit {
  id: string;
  user_id: string;
  token_id: string;
  to: string;
  amount: string;
  sourceChain: string;
  destinationChain: string | null;
  blockNumber: string;
  depositIndex: string;
  depositRoot: string;
  transactionHash: string;
  timestamp: string;
}

export interface IndexedClaim {
  id: string;
  user_id: string;
  token_id: string;
  to: string;
  amount: string;
  sourceChain: string | null;
  destinationChain: string;
  transactionHash: string;
  timestamp: string;
  deposit_id: string | null;
}

export interface IndexedAttestation {
  id: string;
  validator: string;
  sourceChainId: string;
  sourceBlockNumber: string;
  bridgeRoot: string;
  blockTimestamp: string;
}

export interface TransferDashboardResponse {
  Deposit: IndexedDeposit[];
  Claim: IndexedClaim[];
  Attestation: IndexedAttestation[];
}

export type TransferState = "complete" | "claimable" | "attesting" | "pending";

export interface TransferRecord {
  id: string;
  sourceChainId: number;
  destinationChainId: number;
  sourceBlockNumber: number;
  depositIndex: number;
  sourceRoot: `0x${string}`;
  sourceStateRoot: `0x${string}` | null;
  sourceTokenAddress: `0x${string}`;
  sourceChainLabel: string;
  destinationChainLabel: string;
  assetSymbol: string;
  assetName: string;
  assetDecimals: number;
  amount: bigint;
  depositTimestamp: number;
  claimTimestamp: number | null;
  durationSeconds: number;
  attestationCount: number;
  state: TransferState;
  stateLabel: string;
  detailLabel: string;
  depositTransactionHash: string;
  claimTransactionHash: string | null;
  sender: string;
  recipient: string;
  walletIsSender: boolean;
  walletIsRecipient: boolean;
}
