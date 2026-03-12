import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  erc20Abi,
  getAddress,
  http,
  type Address,
} from "viem";
import { SUPPORTED_TOKENS, type SupportedChain } from "@/generated/bridgeConfig";
import { DEFAULT_NATIVE_CURRENCY, supportedChainById } from "@/config/networks";
import type { TokenInfo, QuoteResult, SwapExecution } from "@/types/swap";
import type { TransferRecord } from "@/types/transfers";
import type { Eip1193Provider } from "@/types/wallet";

const sparseMerkleProofComponents = [
  { name: "root", type: "bytes32" },
  { name: "siblings", type: "bytes32[]" },
  { name: "existence", type: "bool" },
  { name: "key", type: "bytes32" },
  { name: "value", type: "bytes32" },
  { name: "auxExistence", type: "bool" },
  { name: "auxKey", type: "bytes32" },
  { name: "auxValue", type: "bytes32" },
] as const;

const bridgeAbi = [
  {
    type: "function",
    name: "deposit",
    stateMutability: "payable",
    inputs: [
      {
        name: "depositParams",
        type: "tuple",
        components: [
          { name: "amount", type: "uint256" },
          { name: "token", type: "address" },
          { name: "to", type: "address" },
          { name: "destinationChain", type: "uint256" },
        ],
      },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "claim",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "claimParams",
        type: "tuple",
        components: [
          { name: "depositIndex", type: "uint256" },
          { name: "sourceChain", type: "uint32" },
          { name: "token", type: "address" },
          { name: "to", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "sourceRoot", type: "bytes32" },
          { name: "blockNumber", type: "uint256" },
          { name: "stateRoot", type: "bytes32" },
          {
            name: "proof",
            type: "tuple",
            components: sparseMerkleProofComponents,
          },
        ],
      },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "getDepositProof",
    stateMutability: "view",
    inputs: [{ name: "depositIndex", type: "uint256" }],
    outputs: [
      {
        name: "proof",
        type: "tuple",
        components: sparseMerkleProofComponents,
      },
    ],
  },
] as const;

const validatorManagerAbi = [
  {
    type: "function",
    name: "isRootVerified",
    stateMutability: "view",
    inputs: [
      {
        name: "params",
        type: "tuple",
        components: [
          { name: "blockNumber", type: "uint256" },
          { name: "bridgeRoot", type: "bytes32" },
          { name: "stateRoot", type: "bytes32" },
          { name: "sourceChainId", type: "uint256" },
        ],
      },
    ],
    outputs: [{ name: "verified", type: "bool" }],
  },
] as const;

interface ClaimabilityResult {
  claimable: boolean;
  stateRoot: `0x${string}`;
}

function normalizeAddress(value: string): Address {
  return getAddress(value);
}

function chainDefinition(chain: SupportedChain) {
  return defineChain({
    id: chain.id,
    name: chain.name,
    nativeCurrency: DEFAULT_NATIVE_CURRENCY,
    rpcUrls: {
      default: { http: [chain.rpcUrl] },
      public: { http: [chain.rpcUrl] },
    },
    blockExplorers: {
      default: { name: chain.name, url: chain.rpcUrl },
    },
  });
}

function publicClient(chainId: number) {
  const chain = supportedChainById(chainId);
  return createPublicClient({
    chain: chainDefinition(chain),
    transport: http(chain.rpcUrl),
  });
}

function walletClient(provider: Eip1193Provider, walletAddress: Address, chainId: number) {
  const chain = supportedChainById(chainId);
  return createWalletClient({
    account: walletAddress,
    chain: chainDefinition(chain),
    transport: custom(provider),
  });
}

function nativeToken(chainId: number): TokenInfo | null {
  return (
    SUPPORTED_TOKENS.find((token) => token.chainId === chainId && token.isNative) ?? null
  );
}

function tokenFallbackMatch(sourceToken: TokenInfo, destinationChainId: number): TokenInfo | null {
  const chainTokens = SUPPORTED_TOKENS.filter(
    (token) => token.chainId === destinationChainId && !token.isNative,
  );

  if (sourceToken.symbol.endsWith("TA")) {
    return chainTokens.find((token) => token.symbol.endsWith("TA")) ?? null;
  }

  if (sourceToken.symbol.endsWith("TB")) {
    return chainTokens.find((token) => token.symbol.endsWith("TB")) ?? null;
  }

  return null;
}

export function sourceChainTokens(chainId: number): TokenInfo[] {
  return SUPPORTED_TOKENS.filter((token) => token.chainId === chainId);
}

export function destinationTokenForSource(
  sourceToken: TokenInfo,
  destinationChainId: number,
): TokenInfo | null {
  if (sourceToken.isNative) {
    return nativeToken(destinationChainId);
  }

  return (
    SUPPORTED_TOKENS.find(
      (token) =>
        token.chainId === destinationChainId &&
        !token.isNative &&
        token.address.toLowerCase() === sourceToken.address.toLowerCase(),
    ) ??
    tokenFallbackMatch(sourceToken, destinationChainId)
  );
}

export async function requestWalletAccounts(provider: Eip1193Provider): Promise<Address[]> {
  const accounts = (await provider.request({
    method: "eth_requestAccounts",
  })) as string[];

  return Array.isArray(accounts) ? accounts.map(normalizeAddress) : [];
}

export async function requestWalletChainId(provider: Eip1193Provider): Promise<number> {
  const rawChainId = await provider.request({ method: "eth_chainId" });
  const normalizedValue = String(rawChainId ?? "");
  const parsedValue = normalizedValue.startsWith("0x")
    ? Number.parseInt(normalizedValue, 16)
    : Number(normalizedValue);

  if (!Number.isInteger(parsedValue) || parsedValue <= 0) {
    throw new Error(`Invalid wallet chain id ${normalizedValue}`);
  }

  return parsedValue;
}

export async function readTokenBalance(
  walletAddress: Address,
  token: TokenInfo,
): Promise<bigint> {
  const client = publicClient(token.chainId);

  if (token.isNative) {
    return client.getBalance({ address: walletAddress });
  }

  return client.readContract({
    address: token.address,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [walletAddress],
  });
}

export async function readTokenAllowance(
  walletAddress: Address,
  token: TokenInfo,
  spender: Address,
): Promise<bigint> {
  if (token.isNative) {
    return 0n;
  }

  return publicClient(token.chainId).readContract({
    address: token.address,
    abi: erc20Abi,
    functionName: "allowance",
    args: [walletAddress, spender],
  });
}

export async function approveBridgeToken(
  provider: Eip1193Provider,
  walletAddress: Address,
  token: TokenInfo,
  amount: bigint,
): Promise<SwapExecution> {
  const chain = supportedChainById(token.chainId);
  const signerClient = walletClient(provider, walletAddress, token.chainId);
  const txHash = await signerClient.writeContract({
    address: token.address,
    abi: erc20Abi,
    functionName: "approve",
    args: [chain.bridge, amount],
    chain: chainDefinition(chain),
    account: walletAddress,
  });

  await publicClient(token.chainId).waitForTransactionReceipt({ hash: txHash });

  return { txHash };
}

export async function depositToBridge(
  provider: Eip1193Provider,
  walletAddress: Address,
  sourceChainId: number,
  destinationChainId: number,
  token: TokenInfo,
  amount: bigint,
): Promise<SwapExecution> {
  const chain = supportedChainById(sourceChainId);
  const signerClient = walletClient(provider, walletAddress, sourceChainId);
  const txHash = await signerClient.writeContract({
    address: chain.bridge,
    abi: bridgeAbi,
    functionName: "deposit",
    args: [
      {
        amount,
        token: token.address,
        to: walletAddress,
        destinationChain: BigInt(destinationChainId),
      },
    ],
    value: token.isNative ? amount : 0n,
    chain: chainDefinition(chain),
    account: walletAddress,
  });

  await publicClient(sourceChainId).waitForTransactionReceipt({ hash: txHash });

  return { txHash };
}

export function bridgePreview(
  sourceChainId: number,
  destinationChainId: number,
  amountIn: bigint,
): QuoteResult {
  return {
    amountOut: amountIn,
    priceImpactBps: 0,
    routeLabel: `${supportedChainById(sourceChainId).name} -> ${supportedChainById(destinationChainId).name}`,
  };
}

export function chainBridgeAddress(chainId: number): Address {
  return supportedChainById(chainId).bridge;
}

export async function readBlockStateRoot(
  chainId: number,
  blockNumber: number,
): Promise<`0x${string}`> {
  const block = (await publicClient(chainId).request({
    method: "eth_getBlockByNumber",
    params: [`0x${blockNumber.toString(16)}`, false],
  })) as {
    stateRoot?: `0x${string}` | null;
  } | null;

  if (!block?.stateRoot) {
    throw new Error(
      `Could not load state root for block ${blockNumber} on ${supportedChainById(chainId).name}`,
    );
  }

  return block.stateRoot;
}

export async function isBridgeTransferClaimable(
  record: Pick<
    TransferRecord,
    "destinationChainId" | "sourceBlockNumber" | "sourceChainId" | "sourceRoot"
  >,
): Promise<ClaimabilityResult> {
  const destinationChain = supportedChainById(record.destinationChainId);
  const stateRoot = await readBlockStateRoot(record.sourceChainId, record.sourceBlockNumber);
  const claimable = await publicClient(record.destinationChainId).readContract({
    address: destinationChain.validatorManager,
    abi: validatorManagerAbi,
    functionName: "isRootVerified",
    args: [
      {
        blockNumber: BigInt(record.sourceBlockNumber),
        bridgeRoot: record.sourceRoot,
        stateRoot,
        sourceChainId: BigInt(record.sourceChainId),
      },
    ],
  });

  return { claimable, stateRoot };
}

export async function claimBridgeTransfer(
  provider: Eip1193Provider,
  walletAddress: Address,
  record: Pick<
    TransferRecord,
    | "amount"
    | "depositIndex"
    | "destinationChainId"
    | "recipient"
    | "sourceBlockNumber"
    | "sourceChainId"
    | "sourceRoot"
    | "sourceStateRoot"
    | "sourceTokenAddress"
  >,
): Promise<SwapExecution> {
  const normalizedRecipient = normalizeAddress(record.recipient);
  if (normalizedRecipient !== walletAddress) {
    throw new Error("The connected wallet must match the transfer recipient to receive funds");
  }

  const stateRoot =
    record.sourceStateRoot ?? (await readBlockStateRoot(record.sourceChainId, record.sourceBlockNumber));
  const sourceBridge = chainBridgeAddress(record.sourceChainId);
  const destinationBridge = chainBridgeAddress(record.destinationChainId);
  const proof = await publicClient(record.sourceChainId).readContract({
    address: sourceBridge,
    abi: bridgeAbi,
    functionName: "getDepositProof",
    args: [BigInt(record.depositIndex)],
  });

  const txHash = await walletClient(
    provider,
    walletAddress,
    record.destinationChainId,
  ).writeContract({
    address: destinationBridge,
    abi: bridgeAbi,
    functionName: "claim",
    args: [
      {
        depositIndex: BigInt(record.depositIndex),
        sourceChain: record.sourceChainId,
        token: normalizeAddress(record.sourceTokenAddress),
        to: normalizedRecipient,
        amount: record.amount,
        sourceRoot: record.sourceRoot,
        blockNumber: BigInt(record.sourceBlockNumber),
        stateRoot,
        proof,
      },
    ] as never,
    chain: chainDefinition(supportedChainById(record.destinationChainId)),
    account: walletAddress,
  });

  await publicClient(record.destinationChainId).waitForTransactionReceipt({ hash: txHash });

  return { txHash };
}
