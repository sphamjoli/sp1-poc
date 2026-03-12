import type { Eip1193Provider, WalletOption } from "@/types/wallet";
interface WalletProviderListeners {
    onAccountsChanged: (accounts: string[]) => void;
    onChainChanged: (chainIdHex: string) => void;
    onDisconnect: () => void;
}
export declare function startWalletDiscovery(onWallet: (wallet: WalletOption) => void): () => void;
export declare function subscribeWalletProvider(provider: Eip1193Provider, listeners: WalletProviderListeners): () => void;
export {};
