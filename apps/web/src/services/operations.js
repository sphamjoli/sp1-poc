const DEFAULT_GRAPHQL_URLS = [
    import.meta.env.VITE_HASURA_URL,
    import.meta.env.VITE_INDEXER_GRAPHQL_URL,
    "http://localhost:8180/v1/graphql",
    "http://localhost:8083/v1/graphql",
].filter(Boolean);
const DEFAULT_NODE_MANAGER_URLS = [
    import.meta.env.VITE_NODE_MANAGER_URL,
    "http://localhost:7011",
    "http://localhost:7001",
].filter(Boolean);
const OPERATIONS_QUERY = `
  query OperationsDashboard {
    BridgeStats_by_pk(id: "BRIDGE_STATS") {
      totalDeposits
      totalClaims
      totalAttestations
      uniqueUsers
      totalVolumeBridged
      activeChains
      lastUpdated
    }
    ChainStats(order_by: { id: asc }) {
      id
      name
      totalDeposits
      totalClaims
      totalVolumeDeposited
      totalVolumeClaimed
      uniqueDepositors
      uniqueClaimers
    }
    Deposit(limit: 120, order_by: { timestamp: desc }) {
      gasPrice
      gasUsed
    }
    Claim(limit: 120, order_by: { timestamp: desc }) {
      gasPrice
      gasUsed
    }
    Attestation(limit: 200, order_by: { blockTimestamp: desc }) {
      gasPrice
      gasUsed
    }
  }
`;
function bigintOrZero(value) {
    if (!value) {
        return 0n;
    }
    try {
        return BigInt(value);
    }
    catch {
        return 0n;
    }
}
function optionalNumber(value) {
    if (!value) {
        return null;
    }
    const parsedValue = Number(value);
    return Number.isFinite(parsedValue) ? parsedValue : null;
}
function averageFeeWei(events) {
    const fees = events
        .map((event) => {
        if (!event.gasPrice || !event.gasUsed) {
            return null;
        }
        return bigintOrZero(event.gasPrice) * bigintOrZero(event.gasUsed);
    })
        .filter((fee) => fee !== null);
    if (fees.length === 0) {
        return null;
    }
    const total = fees.reduce((sum, fee) => sum + fee, 0n);
    return total / BigInt(fees.length);
}
function normalizeRuntimeOverview(runtimeOverview) {
    return {
        owner: runtimeOverview.owner,
        baseChainId: runtimeOverview.baseChainId,
        baseStakeManager: runtimeOverview.baseStakeManager,
        currentEpoch: runtimeOverview.currentEpoch,
        epochDurationSeconds: runtimeOverview.epochDurationSeconds,
        epochsPerYear: runtimeOverview.epochsPerYear,
        activeValidatorCount: runtimeOverview.activeValidatorCount,
        totalBaseStakeAmount: bigintOrZero(runtimeOverview.totalBaseStakeAmount),
        totalPendingRewards: bigintOrZero(runtimeOverview.totalPendingRewards),
        rewardTokenAddress: runtimeOverview.rewardTokenAddress,
        rewardTokenSymbol: runtimeOverview.rewardTokenSymbol,
        rewardTokenDecimals: runtimeOverview.rewardTokenDecimals,
        rewardReserveBalance: bigintOrZero(runtimeOverview.rewardReserveBalance),
        ownerRewardTokenBalance: bigintOrZero(runtimeOverview.ownerRewardTokenBalance),
        lastReconcileAt: runtimeOverview.lastReconcileAt,
        certificateCount: runtimeOverview.certificateCount,
        bridgeWiring: runtimeOverview.bridgeWiring,
        managerOwners: runtimeOverview.managerOwners,
        chainManager: runtimeOverview.chainManager,
        sp1: runtimeOverview.sp1,
        validators: runtimeOverview.validators.map((validator) => ({
            name: validator.name,
            wallet: validator.wallet,
            baseStatus: validator.baseStatus,
            baseStakeAmount: bigintOrZero(validator.baseStakeAmount),
            pendingRewards: bigintOrZero(validator.pendingRewards),
            lastRewardEpoch: validator.lastRewardEpoch,
            attestationCount: validator.attestationCount,
            invalidAttestations: validator.invalidAttestations,
            synced: validator.synced,
        })),
        validatorProcesses: runtimeOverview.validatorProcesses,
        recentCertificates: runtimeOverview.recentCertificates,
    };
}
async function fetchGraphqlData(graphqlUrl) {
    const response = await fetch(graphqlUrl, {
        method: "POST",
        headers: {
            "content-type": "application/json",
        },
        body: JSON.stringify({ query: OPERATIONS_QUERY }),
    });
    if (!response.ok) {
        throw new Error(`Indexer request failed with status ${response.status}`);
    }
    const payload = (await response.json());
    if (payload.errors && payload.errors.length > 0) {
        throw new Error(payload.errors.map((error) => error.message).join("; "));
    }
    if (!payload.data) {
        throw new Error("Indexer returned no data");
    }
    return payload.data;
}
async function fetchRuntimeOverview(nodeManagerUrl) {
    const response = await fetch(`${nodeManagerUrl.replace(/\/$/, "")}/overview`);
    if (!response.ok) {
        throw new Error(`Node manager request failed with status ${response.status}`);
    }
    return (await response.json());
}
async function topUpRewardReserveAt(nodeManagerUrl, amountWei) {
    const response = await fetch(`${nodeManagerUrl.replace(/\/$/, "")}/rewards/top-up`, {
        method: "POST",
        headers: {
            "content-type": "application/json",
        },
        body: JSON.stringify({ amountWei }),
    });
    if (!response.ok) {
        let errorMessage = `Node manager request failed with status ${response.status}`;
        try {
            const payload = (await response.json());
            if (payload.error) {
                errorMessage = payload.error;
            }
        }
        catch {
            // Keep the default status-based error.
        }
        throw new Error(errorMessage);
    }
    return (await response.json());
}
async function firstSuccessful(candidates, fetcher, label) {
    const uniqueCandidates = [...new Set(candidates.filter(Boolean))];
    let lastError = null;
    for (const candidate of uniqueCandidates) {
        try {
            return await fetcher(candidate);
        }
        catch (error) {
            lastError = error instanceof Error ? error : new Error(String(error));
        }
    }
    throw lastError ?? new Error(`No ${label} endpoint configured`);
}
function normalizeSummary(data) {
    return {
        totalDeposits: data.BridgeStats_by_pk?.totalDeposits ?? 0,
        totalClaims: data.BridgeStats_by_pk?.totalClaims ?? 0,
        totalAttestations: data.BridgeStats_by_pk?.totalAttestations ?? 0,
        uniqueUsers: data.BridgeStats_by_pk?.uniqueUsers ?? 0,
        totalVolumeBridged: bigintOrZero(data.BridgeStats_by_pk?.totalVolumeBridged),
        activeChains: data.BridgeStats_by_pk?.activeChains ?? data.ChainStats.length,
        lastUpdated: optionalNumber(data.BridgeStats_by_pk?.lastUpdated),
    };
}
function normalizeChains(data) {
    return data.ChainStats.map((chain) => ({
        id: Number(chain.id),
        name: chain.name,
        totalDeposits: chain.totalDeposits,
        totalClaims: chain.totalClaims,
        totalVolumeDeposited: bigintOrZero(chain.totalVolumeDeposited),
        totalVolumeClaimed: bigintOrZero(chain.totalVolumeClaimed),
        uniqueDepositors: chain.uniqueDepositors,
        uniqueClaimers: chain.uniqueClaimers,
    }));
}
function normalizeFees(data) {
    return {
        averageDepositFeeWei: averageFeeWei(data.Deposit),
        averageClaimFeeWei: averageFeeWei(data.Claim),
        averageAttestationFeeWei: averageFeeWei(data.Attestation),
    };
}
export async function fetchOperationsDashboard(options = {}) {
    const graphqlCandidates = options.graphqlUrl ? [options.graphqlUrl] : DEFAULT_GRAPHQL_URLS;
    const nodeManagerCandidates = options.nodeManagerUrl ? [options.nodeManagerUrl] : DEFAULT_NODE_MANAGER_URLS;
    const [runtimeOverview, graphqlData] = await Promise.all([
        firstSuccessful(nodeManagerCandidates, fetchRuntimeOverview, "node manager"),
        firstSuccessful(graphqlCandidates, fetchGraphqlData, "indexer"),
    ]);
    return {
        summary: normalizeSummary(graphqlData),
        chains: normalizeChains(graphqlData),
        fees: normalizeFees(graphqlData),
        runtime: normalizeRuntimeOverview(runtimeOverview),
    };
}
export async function topUpRewardReserve(amountWei, options = {}) {
    const nodeManagerCandidates = options.nodeManagerUrl ? [options.nodeManagerUrl] : DEFAULT_NODE_MANAGER_URLS;
    return firstSuccessful(nodeManagerCandidates, (nodeManagerUrl) => topUpRewardReserveAt(nodeManagerUrl, amountWei), "node manager");
}
