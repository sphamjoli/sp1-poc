import {
    createWalletClient,
    createPublicClient,
    http,
    parseEther,
    formatEther,
    defineChain,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

// ---------------------------------------------------------
// CONFIG
// ---------------------------------------------------------

const PRIVATE_KEY =
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`

const account = privateKeyToAccount(PRIVATE_KEY)

const CHAINS: Record<number, { rpc: string }> = {
    1: { rpc: "http://localhost:8545" },
    8453: { rpc: "http://localhost:8546" },
}

const CONTRACTS: Record<
    number,
    { bridge: `0x${string}`; tokenA: `0x${string}`; tokenB: `0x${string}` }
> = {
    1: {
        bridge: "0xF1a7a5060f22edA40b1A94a858995fa2bcf5E75A",
        tokenA: "0x2bc0484B5b0FAfFf0a14B858D85E8830621fE0CA",
        tokenB: "0x4c07ce6454D5340591f62fD7d3978B6f42Ef953e",
    },
    8453: {
        bridge: "0xCfecDD44270Fa180d9EC79d7A56f1A8bC9363Ee8",
        tokenA: "0xFeaBf2d20A0Ba3431Aba53079123Ef1F2B017040",
        tokenB: "0x396299f03Df7d8b001bE510f5b1d8d5FFb797e33",
    },
}



const bridgeAbi = require("./out/Bridge.sol/Bridge.json").abi
const tokenAbi = require("./out/BridgeToken.sol/BridgeToken.json").abi

function getClients(chainId: number) {
    const chainConfig = CHAINS[chainId]
    if (!chainConfig) throw new Error(`Unsupported chain ${chainId}`)

    const chain = defineChain({
        id: chainId,
        name: `Chain-${chainId}`,
        nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
        rpcUrls: { default: { http: [chainConfig.rpc] } },
        blockExplorers: { default: { name: "explorer", url: "" } },
    })

    const publicClient = createPublicClient({
        chain,
        transport: http(),
    })

    const walletClient = createWalletClient({
        account,
        chain,
        transport: http(),
    })

    return { publicClient, walletClient }
}


async function simulateAndWrite(chainId: number, address: `0x${string}`, abi: any, fn: string, args: any[]) {
    const { publicClient, walletClient } = getClients(chainId)

    const { request } = await publicClient.simulateContract({
        account,
        address,
        abi,
        functionName: fn,
        args,
    })

    return await walletClient.writeContract(request)
}

async function deposit({
    fromChain,
    token,
    amount,
    destinationChain,
}: {
    fromChain: number
    token: `0x${string}`
    amount: string
    destinationChain: number
}) {
    const amt = parseEther(amount)
    const { publicClient: pub, walletClient: wallet } = getClients(fromChain)

    const bridge = CONTRACTS[fromChain].bridge

    // 1. Approve
    const approve = await pub.simulateContract({
        account,
        address: token,
        abi: tokenAbi,
        functionName: "approve",
        args: [bridge, amt],
    })
    await wallet.writeContract(approve.request)

    // 2. Deposit
    const params = [{
        amount: amt,
        token,
        to: account.address,
        destinationChain,
    }]

    await simulateAndWrite(fromChain, bridge, bridgeAbi, "deposit", params)

    console.log(`Deposit from ${fromChain} → ${destinationChain} complete.`)
}


type MerkleProof = {
    value: `0x${string}`
    key: `0x${string}`
    existence: boolean
    siblings: `0x${string}`[]
}

type ClaimParams = {
    amount: bigint
    token: `0x${string}`
    to: `0x${string}`
    sourceChain: number
    depositIndex: number
    sourceRoot: `0x${string}`
    blockNumber: number
    stateRoot: `0x${string}`
    proof: MerkleProof
}

async function claim(chainId: number, params: ClaimParams) {
    const bridge = CONTRACTS[chainId].bridge

    const tx = await simulateAndWrite(chainId, bridge, bridgeAbi, "claim", [params])
    console.log(`Claim executed on chain ${chainId}`, tx)
}

async function main() {
    await deposit({
        fromChain: 1,
        token: CONTRACTS[1].tokenA,
        amount: "1.0",
        destinationChain: 8453,
    })
        await deposit({
        fromChain: 8453,
        token: CONTRACTS[8453].tokenA,
        amount: "1.0",
        destinationChain: 1,
    })

}

main().catch(console.error)
