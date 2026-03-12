import { CHAIN_LABELS, SUPPORTED_CHAINS, type SupportedChain } from "@/generated/bridgeConfig";
import type { WalletAddEthereumChainParameter } from "@/types/wallet";
export { CHAIN_LABELS, SUPPORTED_CHAINS };
export declare const DEFAULT_NATIVE_CURRENCY: {
    readonly name: "Ether";
    readonly symbol: "ETH";
    readonly decimals: 18;
};
export declare function chainLabel(chainId: number): string;
export declare function supportedChainById(chainId: number): SupportedChain;
export declare function chainHexId(chainId: number): `0x${string}`;
export declare function routeChainIds(sourceChainId: number, destinationChainId: number): number[];
export declare function walletChainParameter(chainId: number): WalletAddEthereumChainParameter;
