import { CHAIN_LABELS, SUPPORTED_CHAINS, type SupportedChain } from "@/generated/bridgeConfig";
import type { WalletAddEthereumChainParameter } from "@/types/wallet";

export { CHAIN_LABELS, SUPPORTED_CHAINS };

export const DEFAULT_NATIVE_CURRENCY = {
  name: "Ether",
  symbol: "ETH",
  decimals: 18,
} as const;

export function chainLabel(chainId: number): string {
  return CHAIN_LABELS[chainId] ?? `Chain ${chainId}`;
}

export function supportedChainById(chainId: number): SupportedChain {
  const supportedChain = SUPPORTED_CHAINS.find((chain) => chain.id === chainId);
  if (!supportedChain) {
    throw new Error(`Unsupported chain ${chainId}`);
  }

  return supportedChain;
}

export function chainHexId(chainId: number): `0x${string}` {
  return `0x${chainId.toString(16)}`;
}

export function routeChainIds(sourceChainId: number, destinationChainId: number): number[] {
  return Array.from(new Set([sourceChainId, destinationChainId]));
}

export function walletChainParameter(chainId: number): WalletAddEthereumChainParameter {
  const supportedChain = supportedChainById(chainId);

  return {
    chainId: chainHexId(supportedChain.id),
    chainName: supportedChain.name,
    rpcUrls: [supportedChain.rpcUrl],
    nativeCurrency: DEFAULT_NATIVE_CURRENCY,
  };
}
