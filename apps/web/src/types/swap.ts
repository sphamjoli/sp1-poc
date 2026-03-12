export type AdapterMode = "local" | "uniswap";

export interface TokenInfo {
  chainId: number;
  address: `0x${string}`;
  symbol: string;
  name: string;
  decimals: number;
  isNative: boolean;
}

export interface QuoteRequest {
  chainId: number;
  fromToken: TokenInfo;
  toToken: TokenInfo;
  amountIn: bigint;
}

export interface QuoteResult {
  amountOut: bigint;
  priceImpactBps: number;
  routeLabel: string;
}

export interface SwapExecution {
  txHash: `0x${string}`;
  explorerUrl?: string;
}

export interface SwapAdapter {
  mode: AdapterMode;
  getBalance(wallet: `0x${string}`, token: TokenInfo): Promise<bigint>;
  getAllowance(wallet: `0x${string}`, spender: `0x${string}`, token: TokenInfo): Promise<bigint>;
  quote(request: QuoteRequest): Promise<QuoteResult>;
  approve(
    wallet: `0x${string}`,
    spender: `0x${string}`,
    token: TokenInfo,
    amount: bigint,
  ): Promise<SwapExecution>;
  swap(wallet: `0x${string}`, request: QuoteRequest): Promise<SwapExecution>;
}

export type SwapStatus =
  | "connecting"
  | "idle"
  | "quoting"
  | "approval-required"
  | "approving"
  | "switching-chain"
  | "ready"
  | "swapping"
  | "success"
  | "error";
