import { createPublicClient, createWalletClient, http, parseEther, formatEther, getContract, defineChain, walletActions, publicActions } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

const PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`
const ETH_RPC_URL = "http://localhost:8545"
const BASE_RPC_URL = "http://localhost:8546"

const account = privateKeyToAccount(PRIVATE_KEY)

const base = defineChain({
    id: 8453,
    name: 'Base',
    nativeCurrency: {
        decimals: 18,
        name: 'Ether',
        symbol: 'ETH',
    },
    rpcUrls: {
        default: {
            http: [BASE_RPC_URL],
            webSocket: [],
        },
    },
    blockExplorers: {
        default: { name: 'Explorer', url: 'https://explorer.zora.energy' },
    },
    contracts: {
        multicall3: {
            address: '0xcA11bde05977b3631167028862bE2a173976CA11',
            blockCreated: 5882,
        },
    },
})

const mainnet = defineChain({
    id: 1,
    name: 'Mainnet',
    nativeCurrency: {
        decimals: 18,
        name: 'Ether',
        symbol: 'ETH',
    },
    rpcUrls: {
        default: {
            http: [ETH_RPC_URL],
            webSocket: [],
        },
    },
    blockExplorers: {
        default: { name: 'Explorer', url: 'https://explorer.zora.energy' },
    },
    contracts: {
        multicall3: {
            address: '0xcA11bde05977b3631167028862bE2a173976CA11',
            blockCreated: 5882,
        },
    },
})

const ethereumClient = createWalletClient({
    account,
    chain: mainnet,
    transport: http(ETH_RPC_URL)
}).extend(publicActions)

const baseClient = createWalletClient({
    account,
    chain: base,
    transport: http(BASE_RPC_URL)
}).extend(publicActions)

const bridgeAbi = require("./out/Bridge.sol/Bridge.json").abi
const tokenAbi = require("./out/BridgeToken.sol/BridgeToken.json").abi


const ethereumAddresses = {
    bridge: "0x3860B063928436F548c3A58A40c4d1d171E78838" as `0x${string}`,
    tokenA: "0xAF185e745b8d404c9cbC1a713D25d93f81c8672c" as `0x${string}`,
    tokenB: "0xA75d83A22BaDdaFB38B78675Ea1535525E302502" as `0x${string}`
}

const baseAddresses = {
    bridge: "0xa0895076F3bDC96b9f7be96c3e3Fc07F11E128d7" as `0x${string}`,
    tokenA: "0xcd649274FD1D77A93895f08EFD82ba617Ed3633d" as `0x${string}`,
    tokenB: "0x077db029EA453516D4cdE06Cae35FBC7a14CF417" as `0x${string}`
}

const ethereumBridge = getContract({
    address: ethereumAddresses.bridge,
    abi: bridgeAbi,
    client: ethereumClient
})

const baseBridge = getContract({
    address: baseAddresses.bridge,
    abi: bridgeAbi,
    client: baseClient
})

const ethereumTokenA = getContract({
    address: ethereumAddresses.tokenA,
    abi: tokenAbi,
    client: ethereumClient
})

const ethereumTokenB = getContract({
    address: ethereumAddresses.tokenB,
    abi: tokenAbi,
    client: ethereumClient
})

const baseTokenA = getContract({
    address: baseAddresses.tokenA,
    abi: tokenAbi,
    client: baseClient
})

const baseTokenB = getContract({
    address: baseAddresses.tokenB,
    abi: tokenAbi,
    client: baseClient
})

async function checkTokenBalances() {
    console.log('=== TOKEN BALANCES ===')

    console.log('\nEthereum:')
    const ethTokenABalance = await ethereumTokenA.read.balanceOf([account.address]) as bigint
    const ethTokenBBalance = await ethereumTokenB.read.balanceOf([account.address]) as bigint
    console.log(`Token A: ${formatEther(ethTokenABalance)}`)
    console.log(`Token B: ${formatEther(ethTokenBBalance)}`)

    console.log('\nBase:')
    const baseTokenABalance = await baseTokenA.read.balanceOf([account.address]) as bigint
    const baseTokenBBalance = await baseTokenB.read.balanceOf([account.address]) as bigint
    console.log(`Token A: ${formatEther(baseTokenABalance)}`)
    console.log(`Token B: ${formatEther(baseTokenBBalance)}`)

    console.log('\nETH Balances:')
    const ethBalance = await ethereumClient.getBalance({ address: account.address })
    const baseEthBalance = await baseClient.getBalance({ address: account.address })
    console.log(`Ethereum: ${formatEther(ethBalance)} ETH`)
    console.log(`Base: ${formatEther(baseEthBalance)} ETH`)
}

async function depositToBase(tokenAddress: `0x${string}`, amount: string) {
    console.log('=== DEPOSIT TO BASE ===')
    console.log(`Depositing ${amount} tokens to Base...`)

    const amountWei = parseEther(amount)

    const token = getContract({
        address: tokenAddress,
        abi: tokenAbi,
        client: ethereumClient
    })

    console.log('Checking allowance...')
    const allowance = await token.read.allowance([account.address, ethereumAddresses.bridge]) as bigint

    if (allowance < amountWei) {
        console.log('Approving tokens...')
        const approveTx = await token.write.approve([ethereumAddresses.bridge, amountWei])
        console.log(`Approve tx: ${approveTx}`)

        await ethereumClient.waitForTransactionReceipt({ hash: approveTx })
        console.log('Approval confirmed')
    }

    console.log('Initiating deposit...')
    const depositTx = await ethereumBridge.write.deposit([
        tokenAddress,
        amountWei,
        8453,
        account.address
    ])

    console.log(`Deposit tx: ${depositTx}`)

    const receipt = await ethereumClient.waitForTransactionReceipt({ hash: depositTx })
    console.log('Deposit confirmed:', receipt.status)
}

async function depositToEthereum(tokenAddress: `0x${string}`, amount: string) {
    console.log('=== DEPOSIT TO ETHEREUM ===')
    console.log(`Depositing ${amount} tokens to Ethereum...`)

    const amountWei = parseEther(amount)

    const token = getContract({
        address: tokenAddress,
        abi: tokenAbi,
        client: baseClient
    })

    console.log('Checking allowance...')
    const allowance = await token.read.allowance([account.address, baseAddresses.bridge]) as bigint

    if (allowance < amountWei) {
        console.log('Approving tokens...')
        const approveTx = await token.write.approve([baseAddresses.bridge, amountWei])
        console.log(`Approve tx: ${approveTx}`)

        await baseClient.waitForTransactionReceipt({ hash: approveTx })
        console.log('Approval confirmed')
    }

    console.log('Initiating deposit...')
    const depositTx = await baseBridge.write.depositToken([
        {
            amount: amountWei,
            who: "0xcA11bde05977b3631167028862bE2a173976CA11" as `0x{string}`,
            token: tokenAddress as `0x{string}`,
            to: "0xcA11bde05977b3631167028862bE2a173976CA11" as `0x{string}`,
            destinationChain: 1
        }
    ])

    console.log(`Deposit tx: ${depositTx}`)

    const receipt = await baseClient.waitForTransactionReceipt({ hash: depositTx })
    console.log('Deposit confirmed:', receipt.status)
}

async function claimOnBase(proof: `0x${string}`, publicValues: `0x${string}`) {
    console.log('=== CLAIM ON BASE ===')
    console.log('Submitting claim...')

    const claimTx = await baseBridge.write.claim([proof, publicValues])
    console.log(`Claim tx: ${claimTx}`)

    const receipt = await baseClient.waitForTransactionReceipt({ hash: claimTx })
    console.log('Claim confirmed:', receipt.status)

    return receipt
}

async function mint(chainId: number, to: `0x${string}`, amount: string) {
    console.log(`=== MINT ON CHAIN ${chainId} ===`)
    console.log(`Minting ${amount} tokens to ${to}...`)
    
    const amountWei = parseEther(amount)
    
    if (chainId === 1) {
        const mintTx = await ethereumTokenA.write.mint([to, amountWei])
        console.log(`Minting tx: ${mintTx}`)

        const receipt = await ethereumClient.waitForTransactionReceipt({ hash: mintTx })
        console.log('Minting confirmed:', receipt.status)
        return receipt
    } else if (chainId === 8453) {
        const mintTx = await baseTokenA.write.mint([to, amountWei])
        console.log(`Minting tx: ${mintTx}`)

        const receipt = await baseClient.waitForTransactionReceipt({ hash: mintTx })
        console.log('Minting confirmed:', receipt.status)
        return receipt
    } else {
        throw new Error(`Unsupported chain ID: ${chainId}`)
    }
}

async function claimOnEthereum(proof: `0x${string}`, publicValues: `0x${string}`) {
    console.log('=== CLAIM ON ETHEREUM ===')
    console.log('Submitting claim...')

    const claimTx = await ethereumBridge.write.claim([proof, publicValues])
    console.log(`Claim tx: ${claimTx}`)

    const receipt = await ethereumClient.waitForTransactionReceipt({ hash: claimTx })
    console.log('Claim confirmed:', receipt.status)

    return receipt
}


async function main() {
    //await checkTokenBalances()

    //  await depositToBase("0x4F7c2894D115AC4b2b6B0544e3471fb10B4dfdF0", "10.0")
   // await mint(1,account.address,"50")
   //  await mint(8453,account.address,"50")
 
    await depositToEthereum(baseAddresses.tokenA, "1.0")
    await depositToEthereum(baseAddresses.tokenA, "1.0")
    await depositToEthereum(baseAddresses.tokenA, "1.0")

    // await claimOnBase(
    //      "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
    //     "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
    // )

    // await claimOnEthereum(
    //     "0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321",
    //     "0x0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba"
    // )
}

main().catch(console.error)