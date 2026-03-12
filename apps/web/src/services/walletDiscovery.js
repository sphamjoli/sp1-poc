export function startWalletDiscovery(onWallet) {
    const announceHandler = (event) => {
        const walletEvent = event;
        if (!walletEvent.detail?.info || !walletEvent.detail.provider) {
            return;
        }
        onWallet({
            info: walletEvent.detail.info,
            provider: walletEvent.detail.provider,
        });
    };
    window.addEventListener("eip6963:announceProvider", announceHandler);
    window.dispatchEvent(new Event("eip6963:requestProvider"));
    return () => {
        window.removeEventListener("eip6963:announceProvider", announceHandler);
    };
}
export function subscribeWalletProvider(provider, listeners) {
    if (!provider.on || !provider.removeListener) {
        return () => undefined;
    }
    const accountsChangedHandler = (accounts) => {
        listeners.onAccountsChanged(Array.isArray(accounts) ? accounts.map(String) : []);
    };
    const chainChangedHandler = (chainIdHex) => {
        listeners.onChainChanged(String(chainIdHex ?? ""));
    };
    const disconnectHandler = () => {
        listeners.onDisconnect();
    };
    provider.on("accountsChanged", accountsChangedHandler);
    provider.on("chainChanged", chainChangedHandler);
    provider.on("disconnect", disconnectHandler);
    return () => {
        provider.removeListener?.("accountsChanged", accountsChangedHandler);
        provider.removeListener?.("chainChanged", chainChangedHandler);
        provider.removeListener?.("disconnect", disconnectHandler);
    };
}
