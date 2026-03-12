import type { QuoteRequest, QuoteResult, SwapAdapter, SwapExecution, TokenInfo } from "@/types/swap";

const DEFAULT_BALANCE = 1_000n * 10n ** 18n;
const MAX_ALLOWANCE = (1n << 255n) - 1n;

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function randomHash(prefix: string): `0x${string}` {
  const seed = `${prefix}-${Date.now()}-${Math.random()}`;
  let hex = "";
  for (let index = 0; index < seed.length; index += 1) {
    hex += seed.charCodeAt(index).toString(16).padStart(2, "0");
  }
  return `0x${hex.slice(0, 64).padEnd(64, "0")}` as `0x${string}`;
}

function balanceKey(wallet: `0x${string}`, token: TokenInfo): string {
  return `${wallet.toLowerCase()}:${token.chainId}:${token.address.toLowerCase()}`;
}

function allowanceKey(wallet: `0x${string}`, spender: `0x${string}`, token: TokenInfo): string {
  return `${wallet.toLowerCase()}:${spender.toLowerCase()}:${token.chainId}:${token.address.toLowerCase()}`;
}

export class LocalMockAdapter implements SwapAdapter {
  readonly mode = "local" as const;
  private readonly balances = new Map<string, bigint>();
  private readonly allowances = new Map<string, bigint>();

  async getBalance(wallet: `0x${string}`, token: TokenInfo): Promise<bigint> {
    const key = balanceKey(wallet, token);
    if (!this.balances.has(key)) {
      this.balances.set(key, DEFAULT_BALANCE);
    }
    return this.balances.get(key) ?? 0n;
  }

  async getAllowance(
    wallet: `0x${string}`,
    spender: `0x${string}`,
    token: TokenInfo,
  ): Promise<bigint> {
    if (token.isNative) {
      return MAX_ALLOWANCE;
    }

    const key = allowanceKey(wallet, spender, token);
    return this.allowances.get(key) ?? 0n;
  }

  async quote(request: QuoteRequest): Promise<QuoteResult> {
    await delay(250);
    if (request.fromToken.chainId !== request.toToken.chainId) {
      throw new Error("Local adapter only supports same-chain swaps");
    }

    const amountOut = (request.amountIn * 997n) / 1000n;
    const priceImpactBps = Number(request.amountIn / (10n ** 18n)) > 100 ? 45 : 12;

    return {
      amountOut,
      priceImpactBps,
      routeLabel: `MockPool ${request.fromToken.symbol}/${request.toToken.symbol}`,
    };
  }

  async approve(
    wallet: `0x${string}`,
    spender: `0x${string}`,
    token: TokenInfo,
    amount: bigint,
  ): Promise<SwapExecution> {
    if (token.isNative) {
      throw new Error("Native assets do not require approval");
    }

    await delay(800);
    const key = allowanceKey(wallet, spender, token);
    this.allowances.set(key, amount);

    return {
      txHash: randomHash("approve"),
      explorerUrl: undefined,
    };
  }

  async swap(wallet: `0x${string}`, request: QuoteRequest): Promise<SwapExecution> {
    await delay(1_200);

    const quote = await this.quote(request);
    const fromKey = balanceKey(wallet, request.fromToken);
    const toKey = balanceKey(wallet, request.toToken);

    const fromBalance = await this.getBalance(wallet, request.fromToken);
    const toBalance = await this.getBalance(wallet, request.toToken);

    if (fromBalance < request.amountIn) {
      throw new Error("Insufficient balance for swap");
    }

    this.balances.set(fromKey, fromBalance - request.amountIn);
    this.balances.set(toKey, toBalance + quote.amountOut);

    return {
      txHash: randomHash("swap"),
      explorerUrl: undefined,
    };
  }
}
