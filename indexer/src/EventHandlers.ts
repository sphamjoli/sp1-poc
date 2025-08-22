import { Bridge, User, Token, Deposit, Claim, BridgeStats, DailyStats, ChainStats } from "generated";

Bridge.Deposit.handler(async ({ event, context }: { event: any; context: any }) => {
  const userId = event.params.who.toString();
  const tokenId = event.params.token.toString();
  const depositId = `${event.transaction.hash}-${event.logIndex}`;
  const dateId = new Date(Number(event.block.timestamp) * 1000).toISOString().split('T')[0];
  const chainId = BigInt(event.chainId);

  const user = await context.User.getOrCreate({
    id: userId,
    depositCount: 0,
    claimCount: 0,
    totalDeposited: 0n,
    totalClaimed: 0n,
    lastActivityAt: event.block.timestamp,
  });

  const updatedUser: User = {
    ...user,
    depositCount: user.depositCount + 1,
    totalDeposited: user.totalDeposited + event.params.amount,
    lastActivityAt: event.block.timestamp,
    firstDepositAt: user.firstDepositAt ?? event.block.timestamp,
  };
  context.User.set(updatedUser);

  const token = await context.Token.getOrCreate({
    id: tokenId,
    symbol: tokenId === "0x0000000000000000000000000000000000000000" ? "ETH" : "UNKNOWN",
    name: tokenId === "0x0000000000000000000000000000000000000000" ? "Ethereum" : "Unknown Token",
    decimals: tokenId === "0x0000000000000000000000000000000000000000" ? 18 : 18,
    totalDeposited: 0n,
    totalClaimed: 0n,
    bridgeBalance: 0n,
    uniqueDepositors: 0,
    uniqueClaimers: 0,
    isActive: true,
  });

  const isNewDepositor = token.totalDeposited === 0n || user.depositCount === 1;
  const updatedToken: Token = {
    ...token,
    totalDeposited: token.totalDeposited + event.params.amount,
    bridgeBalance: token.bridgeBalance + event.params.amount,
    uniqueDepositors: isNewDepositor ? token.uniqueDepositors + 1 : token.uniqueDepositors,
  };
  context.Token.set(updatedToken);

  const deposit: Deposit = {
    id: depositId,
    user_id: userId,
    amount: event.params.amount,
    token_id: tokenId,
    to: event.params.to?.toString() || userId,
    destinationChain: event.params.destinationChain ? BigInt(event.params.destinationChain) : undefined,
    transactionHash: event.transaction.hash,
    blockNumber: event.block.number,
    timestamp: event.block.timestamp,
    logIndex: event.logIndex,
    gasPrice: 0n,
    gasUsed: 0n,
    isClaimed: false,
    sourceChain: chainId,
  };
  context.Deposit.set(deposit);

  const bridgeStats = await context.BridgeStats.getOrCreate({
    id: "BRIDGE_STATS",
    totalDeposits: 0,
    totalClaims: 0,
    uniqueUsers: 0,
    supportedTokens: 0,
    totalVolumeBridged: 0n,
    activeChains: 0,
    lastUpdated: event.block.timestamp,
  });

  const isNewUser = user.depositCount === 1 && user.claimCount === 0;
  const updatedBridgeStats: BridgeStats = {
    ...bridgeStats,
    totalDeposits: bridgeStats.totalDeposits + 1,
    uniqueUsers: isNewUser ? bridgeStats.uniqueUsers + 1 : bridgeStats.uniqueUsers,
    totalVolumeBridged: bridgeStats.totalVolumeBridged + event.params.amount,
    lastUpdated: event.block.timestamp,
  };
  context.BridgeStats.set(updatedBridgeStats);

  const dailyStats = await context.DailyStats.getOrCreate({
    id: dateId,
    date: BigInt(Math.floor(Number(event.block.timestamp) / 86400) * 86400),
    dailyDeposits: 0,
    dailyClaims: 0,
    dailyActiveUsers: 0,
    dailyVolume: 0n,
    newUsers: 0,
    avgDepositGasPrice: undefined,
    avgClaimGasPrice: undefined,
  });

  const updatedDailyStats: DailyStats = {
    ...dailyStats,
    dailyDeposits: dailyStats.dailyDeposits + 1,
    dailyActiveUsers: dailyStats.dailyActiveUsers + (isNewUser ? 1 : 0),
    dailyVolume: dailyStats.dailyVolume + event.params.amount,
    newUsers: dailyStats.newUsers + (isNewUser ? 1 : 0),
    avgDepositGasPrice: undefined,
  };
  context.DailyStats.set(updatedDailyStats);

  const chainStats = await context.ChainStats.getOrCreate({
    id: chainId.toString(),
    name: getChainName(event.chainId),
    totalDeposits: 0,
    totalClaims: 0,
    totalVolumeDeposited: 0n,
    totalVolumeClaimed: 0n,
    uniqueDepositors: 0,
    uniqueClaimers: 0,
    isActive: true,
  });

  const updatedChainStats: ChainStats = {
    ...chainStats,
    totalDeposits: chainStats.totalDeposits + 1,
    totalVolumeDeposited: chainStats.totalVolumeDeposited + event.params.amount,
    uniqueDepositors: isNewDepositor ? chainStats.uniqueDepositors + 1 : chainStats.uniqueDepositors,
  };
  context.ChainStats.set(updatedChainStats);

  context.log.info(`Deposit processed: ${event.params.amount} ${token.symbol} from ${userId} on chain ${event.chainId}`);
});

Bridge.Claimed.handler(async ({ event, context }: { event: any; context: any }) => {
  const userId = event.params.who.toString();
  const tokenId = event.params.token.toString();
  const claimId = `${event.transaction.hash}-${event.logIndex}`;
  const dateId = new Date(Number(event.block.timestamp) * 1000).toISOString().split('T')[0];
  const chainId = BigInt(event.chainId);

  const user = await context.User.getOrThrow(
    userId,
    `User ${userId} must exist before claiming`
  );

  const updatedUser: User = {
    ...user,
    claimCount: user.claimCount + 1,
    totalClaimed: user.totalClaimed + event.params.amount,
    lastActivityAt: event.block.timestamp,
  };
  context.User.set(updatedUser);

  const token = await context.Token.getOrThrow(
    tokenId,
    `Token ${tokenId} must exist before claiming`
  );

  const isNewClaimer = user.claimCount === 1;
  const updatedToken: Token = {
    ...token,
    totalClaimed: token.totalClaimed + event.params.amount,
    bridgeBalance: token.bridgeBalance - event.params.amount,
    uniqueClaimers: isNewClaimer ? token.uniqueClaimers + 1 : token.uniqueClaimers,
  };
  context.Token.set(updatedToken);

  const claim: Claim = {
    id: claimId,
    user_id: userId,
    amount: event.params.amount,
    token_id: tokenId,
    to: event.params.to?.toString() || userId,
    transactionHash: event.transaction.hash,
    blockNumber: event.block.number,
    timestamp: event.block.timestamp,
    logIndex: event.logIndex,
    gasPrice: 0n,
    gasUsed: 0n,
    proofBytes: event.params.proofBytes || "0x",
    publicInputs: event.params.publicInputs || "0x",
    deposit_id: undefined,
    sourceChain: event.params.sourceChain ? BigInt(event.params.sourceChain) : undefined,
    destinationChain: chainId,
  };
  context.Claim.set(claim);

  const bridgeStats = await context.BridgeStats.getOrThrow("BRIDGE_STATS");
  const updatedBridgeStats: BridgeStats = {
    ...bridgeStats,
    totalClaims: bridgeStats.totalClaims + 1,
    lastUpdated: event.block.timestamp,
  };
  context.BridgeStats.set(updatedBridgeStats);

  const dailyStats = await context.DailyStats.getOrCreate({
    id: dateId,
    date: BigInt(Math.floor(Number(event.block.timestamp) / 86400) * 86400),
    dailyDeposits: 0,
    dailyClaims: 0,
    dailyActiveUsers: 0,
    dailyVolume: 0n,
    newUsers: 0,
    avgDepositGasPrice: undefined,
    avgClaimGasPrice: undefined,
  });

  const updatedDailyStats: DailyStats = {
    ...dailyStats,
    dailyClaims: dailyStats.dailyClaims + 1,
    avgClaimGasPrice: undefined,
  };
  context.DailyStats.set(updatedDailyStats);

  const chainStats = await context.ChainStats.getOrCreate({
    id: chainId.toString(),
    name: getChainName(event.chainId),
    totalDeposits: 0,
    totalClaims: 0,
    totalVolumeDeposited: 0n,
    totalVolumeClaimed: 0n,
    uniqueDepositors: 0,
    uniqueClaimers: 0,
    isActive: true,
  });

  const updatedChainStats: ChainStats = {
    ...chainStats,
    totalClaims: chainStats.totalClaims + 1,
    totalVolumeClaimed: chainStats.totalVolumeClaimed + event.params.amount,
    uniqueClaimers: isNewClaimer ? chainStats.uniqueClaimers + 1 : chainStats.uniqueClaimers,
  };
  context.ChainStats.set(updatedChainStats);

  context.log.info(`Claimed processed: ${event.params.amount} ${token.symbol} by ${userId} on chain ${event.chainId}`);
});

function getChainName(chainId: number): string {
  const chainNames: Record<number, string> = {
    1: "Ethereum",
    8453: "Base",
  };
  return chainNames[chainId] || `Chain ${chainId}`;
}