import { CHAIN_LABELS, SUPPORTED_CHAINS } from "@/generated/bridgeConfig";
export { CHAIN_LABELS, SUPPORTED_CHAINS };
export const DEFAULT_NATIVE_CURRENCY = {
    name: "Ether",
    symbol: "ETH",
    decimals: 18,
};
export function chainLabel(chainId) {
    return CHAIN_LABELS[chainId] ?? `Chain ${chainId}`;
}
export function supportedChainById(chainId) {
    const supportedChain = SUPPORTED_CHAINS.find((chain) => chain.id === chainId);
    if (!supportedChain) {
        throw new Error(`Unsupported chain ${chainId}`);
    }
    return supportedChain;
}
export function chainHexId(chainId) {
    return `0x${chainId.toString(16)}`;
}
export function routeChainIds(sourceChainId, destinationChainId) {
    return Array.from(new Set([sourceChainId, destinationChainId]));
}
export function walletChainParameter(chainId) {
    const supportedChain = supportedChainById(chainId);
    return {
        chainId: chainHexId(supportedChain.id),
        chainName: supportedChain.name,
        rpcUrls: [supportedChain.rpcUrl],
        nativeCurrency: DEFAULT_NATIVE_CURRENCY,
    };
}
