import type { Eip1193Provider } from "@/types/wallet";
export declare function addWalletChain(provider: Eip1193Provider, chainId: number): Promise<void>;
export declare function addWalletRouteChains(provider: Eip1193Provider, sourceChainId: number, destinationChainId: number): Promise<number[]>;
export declare function switchWalletChain(provider: Eip1193Provider, chainId: number): Promise<void>;
