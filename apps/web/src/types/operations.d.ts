export interface ValidatorChainSync {
    chain_id: number;
    status: string;
    expected_status: string;
}
export interface ValidatorRuntimeStatus {
    name: string;
    wallet: string;
    baseStatus: string;
    baseStakeAmount: bigint;
    pendingRewards: bigint;
    lastRewardEpoch: string;
    attestationCount: string;
    invalidAttestations: string;
    synced: ValidatorChainSync[];
}
export interface CertificateActivity {
    validator: string;
    targetChainId: number;
    issuedAt: number;
    expiresAt: number;
    certificateHex: string;
    signer: string;
}
export interface ChainManagerStatus {
    status: string;
    bind: string;
    chainIds: number[];
    startedAt: number;
}
export interface Sp1Status {
    status: string;
    startedAt: number;
    lastRunAt: number | null;
    lastFinalizedSourceChainId: number | null;
    lastFinalizedBlockNumber: number | null;
    lastError: string | null;
}
export interface ValidatorProcessStatus {
    validator: string;
    lastHeartbeatAt: number | null;
    lastError: string | null;
    submittedCount: number;
    pendingCount: number;
    retryingCount: number;
}
export interface BridgeSummary {
    totalDeposits: number;
    totalClaims: number;
    totalAttestations: number;
    uniqueUsers: number;
    totalVolumeBridged: bigint;
    activeChains: number;
    lastUpdated: number | null;
}
export interface ChainSummary {
    id: number;
    name: string;
    totalDeposits: number;
    totalClaims: number;
    totalVolumeDeposited: bigint;
    totalVolumeClaimed: bigint;
    uniqueDepositors: number;
    uniqueClaimers: number;
}
export interface FeeSummary {
    averageDepositFeeWei: bigint | null;
    averageClaimFeeWei: bigint | null;
    averageAttestationFeeWei: bigint | null;
}
export interface RuntimeOverview {
    owner: string;
    baseChainId: number;
    baseStakeManager: string;
    currentEpoch: string;
    epochDurationSeconds: string;
    epochsPerYear: string;
    activeValidatorCount: number;
    totalBaseStakeAmount: bigint;
    totalPendingRewards: bigint;
    rewardTokenAddress: string;
    rewardTokenSymbol: string;
    rewardTokenDecimals: number;
    rewardReserveBalance: bigint;
    ownerRewardTokenBalance: bigint;
    lastReconcileAt: number | null;
    certificateCount: number;
    bridgeWiring: string[];
    managerOwners: string[];
    chainManager: ChainManagerStatus | null;
    sp1: Sp1Status | null;
    validators: ValidatorRuntimeStatus[];
    validatorProcesses: ValidatorProcessStatus[];
    recentCertificates: CertificateActivity[];
}
export interface OperationsDashboardData {
    summary: BridgeSummary;
    chains: ChainSummary[];
    fees: FeeSummary;
    runtime: RuntimeOverview;
}
export interface RewardTopUpResult {
    status: string;
    chainId: number;
    stakeManager: string;
    rewardToken: string;
    amountWei: string;
    approveTransactionHash: string;
    topUpTransactionHash: string;
}
