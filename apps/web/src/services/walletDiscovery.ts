import type {
  Eip1193Provider,
  Eip6963ProviderDetail,
  WalletOption,
} from "@/types/wallet";

interface WalletProviderListeners {
  onAccountsChanged: (accounts: string[]) => void;
  onChainChanged: (chainIdHex: string) => void;
  onDisconnect: () => void;
}

export function startWalletDiscovery(onWallet: (wallet: WalletOption) => void): () => void {
  const announceHandler = (event: Event): void => {
    const walletEvent = event as CustomEvent<Eip6963ProviderDetail>;
    if (!walletEvent.detail?.info || !walletEvent.detail.provider) {
      return;
    }

    onWallet({
      info: walletEvent.detail.info,
      provider: walletEvent.detail.provider,
    });
  };

  window.addEventListener("eip6963:announceProvider", announceHandler as EventListener);
  window.dispatchEvent(new Event("eip6963:requestProvider"));

  return () => {
    window.removeEventListener("eip6963:announceProvider", announceHandler as EventListener);
  };
}

export function subscribeWalletProvider(
  provider: Eip1193Provider,
  listeners: WalletProviderListeners,
): () => void {
  if (!provider.on || !provider.removeListener) {
    return () => undefined;
  }

  const accountsChangedHandler = (accounts: unknown): void => {
    listeners.onAccountsChanged(Array.isArray(accounts) ? accounts.map(String) : []);
  };
  const chainChangedHandler = (chainIdHex: unknown): void => {
    listeners.onChainChanged(String(chainIdHex ?? ""));
  };
  const disconnectHandler = (): void => {
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
