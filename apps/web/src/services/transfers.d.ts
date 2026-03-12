import type { IndexedAttestation, IndexedClaim, IndexedDeposit, TransferRecord } from "@/types/transfers";
interface FetchTransferRecordsOptions {
    limit?: number;
    claimLimit?: number;
    attestationLimit?: number;
    graphqlUrl?: string;
    includeRuntimeState?: boolean;
}
interface RuntimeTransferState {
    claimable: boolean;
    sourceStateRoot: `0x${string}` | null;
}
export declare function buildTransferRecords(walletAddress: string, deposits: IndexedDeposit[], claims: IndexedClaim[], attestations: IndexedAttestation[], currentTimestampSeconds?: number): TransferRecord[];
export declare function applyTransferRuntimeState(records: TransferRecord[], runtimeStateByKey: Map<string, RuntimeTransferState>): TransferRecord[];
export declare function markTransferRecordReceived(record: TransferRecord, claimTimestampSeconds: number, claimTransactionHash: string | null): TransferRecord;
export declare function fetchTransferRecords(walletAddress: string, options?: FetchTransferRecordsOptions): Promise<TransferRecord[]>;
export {};
