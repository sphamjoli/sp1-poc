import type { QuoteRequest, QuoteResult, SwapAdapter, SwapExecution, TokenInfo } from "@/types/swap";

export class UniswapV3Adapter implements SwapAdapter {
  readonly mode = "uniswap" as const;

  async getBalance(_wallet: `0x${string}`, _token: TokenInfo): Promise<bigint> {
    throw new Error("Uniswap adapter not configured. Set RPC + wallet integration first.");
  }

  async getAllowance(
    _wallet: `0x${string}`,
    _spender: `0x${string}`,
    _token: TokenInfo,
  ): Promise<bigint> {
    throw new Error("Uniswap adapter not configured. Set RPC + wallet integration first.");
  }

  async quote(_request: QuoteRequest): Promise<QuoteResult> {
    throw new Error("Uniswap quote path is not configured yet.");
  }

  async approve(
    _wallet: `0x${string}`,
    _spender: `0x${string}`,
    _token: TokenInfo,
    _amount: bigint,
  ): Promise<SwapExecution> {
    throw new Error("Uniswap approve path is not configured yet.");
  }

  async swap(_wallet: `0x${string}`, _request: QuoteRequest): Promise<SwapExecution> {
    throw new Error("Uniswap swap path is not configured yet.");
  }
}
