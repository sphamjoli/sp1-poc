import type { TokenInfo } from "@/types/swap";
export interface SupportedChain {
    id: number;
    name: string;
    rpcUrl: string;
    bridge: `0x${string}`;
    validatorManager: `0x${string}`;
}
export declare const SUPPORTED_CHAINS: SupportedChain[];
export declare const CHAIN_LABELS: Record<number, string>;
export declare const SUPPORTED_TOKENS: TokenInfo[];
export declare const DEFAULT_CHAIN_ID = 31338;
export declare const SWAP_SPENDER: `0x${string}`;
