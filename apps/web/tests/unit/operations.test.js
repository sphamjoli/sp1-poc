import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchOperationsDashboard, topUpRewardReserve } from "@/services/operations";
describe("operations dashboard service", () => {
    afterEach(() => {
        vi.restoreAllMocks();
    });
    it("normalizes node-manager and indexer responses", async () => {
        const fetchMock = vi
            .fn()
            .mockResolvedValueOnce(new Response(JSON.stringify({
            owner: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            baseChainId: 8453,
            baseStakeManager: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
            currentEpoch: "14",
            epochDurationSeconds: "600",
            epochsPerYear: "52560",
            activeValidatorCount: 5,
            totalBaseStakeAmount: "1000000000000000000000",
            totalPendingRewards: "5000000000000000000",
            rewardTokenAddress: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
            rewardTokenSymbol: "BBTA",
            rewardTokenDecimals: 18,
            rewardReserveBalance: "25000000000000000000",
            ownerRewardTokenBalance: "800000000000000000000",
            lastReconcileAt: 1_700_000_000,
            certificateCount: 3,
            bridgeWiring: [],
            managerOwners: [],
            chainManager: {
                status: "ok",
                bind: "127.0.0.1:3010",
                chainIds: [1, 8453],
                startedAt: 1_700_000_000,
            },
            sp1: {
                status: "ok",
                startedAt: 1_700_000_000,
                lastRunAt: 1_700_000_010,
                lastFinalizedSourceChainId: 1,
                lastFinalizedBlockNumber: 25,
                lastError: null,
            },
            validators: [
                {
                    name: "alice",
                    wallet: "0x328809Bc894f92807417D2dAD6b7C998c1aFdac6",
                    baseStatus: "Active",
                    baseStakeAmount: "200000000000000000000",
                    pendingRewards: "1000000000000000000",
                    lastRewardEpoch: "13",
                    attestationCount: "7",
                    invalidAttestations: "0",
                    synced: [],
                },
            ],
            validatorProcesses: [
                {
                    validator: "alice",
                    lastHeartbeatAt: 1_700_000_020,
                    lastError: null,
                    submittedCount: 1,
                    pendingCount: 0,
                    retryingCount: 0,
                },
            ],
            recentCertificates: [
                {
                    validator: "0x328809Bc894f92807417D2dAD6b7C998c1aFdac6",
                    targetChainId: 8453,
                    issuedAt: 1_700_000_001,
                    expiresAt: 1_700_000_601,
                    certificateHex: "0x1234",
                    signer: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                },
            ],
        }), { status: 200 }))
            .mockResolvedValueOnce(new Response(JSON.stringify({
            data: {
                BridgeStats_by_pk: {
                    totalDeposits: 10,
                    totalClaims: 8,
                    totalAttestations: 25,
                    uniqueUsers: 3,
                    totalVolumeBridged: "2000000000000000000",
                    activeChains: 2,
                    lastUpdated: "1700000010",
                },
                ChainStats: [
                    {
                        id: "1",
                        name: "Ethereum",
                        totalDeposits: 10,
                        totalClaims: 8,
                        totalVolumeDeposited: "2000000000000000000",
                        totalVolumeClaimed: "1000000000000000000",
                        uniqueDepositors: 3,
                        uniqueClaimers: 2,
                    },
                ],
                Deposit: [{ gasPrice: "10", gasUsed: "2" }],
                Claim: [{ gasPrice: "8", gasUsed: "4" }],
                Attestation: [{ gasPrice: "3", gasUsed: "5" }],
            },
        }), { status: 200 }));
        vi.stubGlobal("fetch", fetchMock);
        const dashboard = await fetchOperationsDashboard({
            nodeManagerUrl: "http://localhost:7011",
            graphqlUrl: "http://localhost:8180/v1/graphql",
        });
        expect(dashboard.runtime.currentEpoch).toBe("14");
        expect(dashboard.runtime.baseStakeManager).toBe("0x5FbDB2315678afecb367f032d93F642f64180aa3");
        expect(dashboard.runtime.totalBaseStakeAmount).toBe(1000000000000000000000n);
        expect(dashboard.runtime.validators[0]?.pendingRewards).toBe(1000000000000000000n);
        expect(dashboard.runtime.rewardTokenSymbol).toBe("BBTA");
        expect(dashboard.runtime.rewardReserveBalance).toBe(25000000000000000000n);
        expect(dashboard.summary.totalAttestations).toBe(25);
        expect(dashboard.fees.averageDepositFeeWei).toBe(20n);
        expect(dashboard.fees.averageClaimFeeWei).toBe(32n);
        expect(dashboard.fees.averageAttestationFeeWei).toBe(15n);
    });
    it("submits reward reserve top-up requests", async () => {
        const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({
            status: "ok",
            chainId: 31339,
            stakeManager: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
            rewardToken: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
            amountWei: "1000000000000000000",
            approveTransactionHash: "0x1111111111111111111111111111111111111111111111111111111111111111",
            topUpTransactionHash: "0x2222222222222222222222222222222222222222222222222222222222222222",
        }), { status: 200 }));
        vi.stubGlobal("fetch", fetchMock);
        const result = await topUpRewardReserve("1000000000000000000", {
            nodeManagerUrl: "http://localhost:7011",
        });
        expect(fetchMock).toHaveBeenCalledWith("http://localhost:7011/rewards/top-up", expect.objectContaining({
            method: "POST",
            body: JSON.stringify({ amountWei: "1000000000000000000" }),
        }));
        expect(result.topUpTransactionHash).toBe("0x2222222222222222222222222222222222222222222222222222222222222222");
    });
});
