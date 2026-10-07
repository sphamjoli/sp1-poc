export function serializeIndexerChains(chains: readonly { id: number; name: string }[]): string {
  const chainLabels = Object.fromEntries(chains.map((chain) => [chain.id, chain.name]));

  return `export const CHAIN_NAMES: Record<number, string> = ${JSON.stringify(chainLabels, null, 2)};

export function chainName(chainId: number): string {
  return CHAIN_NAMES[chainId] ?? \`Chain \${chainId}\`;
}
`;
}
