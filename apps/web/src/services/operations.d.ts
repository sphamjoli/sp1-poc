import type { OperationsDashboardData, RewardTopUpResult } from "@/types/operations";
interface FetchOperationsOptions {
    graphqlUrl?: string;
    nodeManagerUrl?: string;
}
export declare function fetchOperationsDashboard(options?: FetchOperationsOptions): Promise<OperationsDashboardData>;
export declare function topUpRewardReserve(amountWei: string, options?: Pick<FetchOperationsOptions, "nodeManagerUrl">): Promise<RewardTopUpResult>;
export {};
