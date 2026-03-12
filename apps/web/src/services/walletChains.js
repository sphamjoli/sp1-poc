import { chainHexId, routeChainIds, supportedChainById, walletChainParameter, } from "@/config/networks";
function providerErrorCode(error) {
    if (typeof error !== "object" || error === null || !("code" in error)) {
        return null;
    }
    const errorCode = error.code;
    return typeof errorCode === "number" ? errorCode : null;
}
export async function addWalletChain(provider, chainId) {
    supportedChainById(chainId);
    await provider.request({
        method: "wallet_addEthereumChain",
        params: [walletChainParameter(chainId)],
    });
}
export async function addWalletRouteChains(provider, sourceChainId, destinationChainId) {
    const chainIds = routeChainIds(sourceChainId, destinationChainId);
    for (const chainId of chainIds) {
        await addWalletChain(provider, chainId);
    }
    return chainIds;
}
export async function switchWalletChain(provider, chainId) {
    supportedChainById(chainId);
    const chainIdHex = chainHexId(chainId);
    const switchRequest = {
        method: "wallet_switchEthereumChain",
        params: [{ chainId: chainIdHex }],
    };
    try {
        await provider.request(switchRequest);
    }
    catch (error) {
        if (providerErrorCode(error) !== 4902) {
            throw error;
        }
        await addWalletChain(provider, chainId);
        await provider.request(switchRequest);
    }
}
