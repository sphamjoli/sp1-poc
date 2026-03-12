export interface Eip1193RequestArguments {
  method: string;
  params?: readonly unknown[] | object;
}

export interface WalletNativeCurrency {
  name: string;
  symbol: string;
  decimals: number;
}

export interface WalletAddEthereumChainParameter {
  chainId: `0x${string}`;
  chainName: string;
  rpcUrls: string[];
  nativeCurrency: WalletNativeCurrency;
  blockExplorerUrls?: string[];
  iconUrls?: string[];
}

export interface Eip1193Provider {
  request(arguments_: Eip1193RequestArguments): Promise<unknown>;
  on?(eventName: string, listener: (...arguments_: unknown[]) => void): void;
  removeListener?(eventName: string, listener: (...arguments_: unknown[]) => void): void;
}

export interface Eip6963ProviderInfo {
  uuid: string;
  name: string;
  icon: string;
  rdns: string;
}

export interface Eip6963ProviderDetail {
  info: Eip6963ProviderInfo;
  provider: Eip1193Provider;
}

export interface WalletOption {
  info: Eip6963ProviderInfo;
  provider: Eip1193Provider;
}
