import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { SUPPORTED_CHAINS, chainLabel } from "@/config/networks";
import { destinationTokenForSource, sourceChainTokens, } from "@/services/bridge";
import { fetchTransferRecords } from "@/services/transfers";
import { useSwapStore } from "@/stores/swap";
import { formatUnits } from "@/utils/amount";
import { formatTimestamp, shortenAddress } from "@/utils/format";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const swapStore = useSwapStore();
const balanceRows = ref([]);
const transferRecords = ref([]);
const loading = ref(false);
const errorMessage = ref("");
const lastSyncedAt = ref(null);
let refreshTimer = null;
const walletLabel = computed(() => swapStore.walletAddress ? shortenAddress(swapStore.walletAddress, 5) : "Not connected");
const sentTransferCount = computed(() => transferRecords.value.filter((record) => record.walletIsSender).length);
const receivedTransferCount = computed(() => transferRecords.value.filter((record) => record.walletIsRecipient && record.claimTransactionHash !== null).length);
const waitingTransferCount = computed(() => transferRecords.value.filter((record) => record.walletIsRecipient && record.claimTransactionHash === null).length);
const chainSections = computed(() => SUPPORTED_CHAINS.map((chain) => ({
    chainId: chain.id,
    chainLabel: chainLabel(chain.id),
    rows: balanceRows.value
        .filter((row) => row.token.chainId === chain.id &&
        (row.balance > 0n || row.sent > 0n || row.received > 0n || row.waiting > 0n))
        .sort((left, right) => {
        if (left.token.isNative !== right.token.isNative) {
            return left.token.isNative ? -1 : 1;
        }
        const leftActivity = left.sent + left.received + left.waiting;
        const rightActivity = right.sent + right.received + right.waiting;
        if (leftActivity !== rightActivity) {
            return leftActivity > rightActivity ? -1 : 1;
        }
        if (left.balance !== right.balance) {
            return left.balance > right.balance ? -1 : 1;
        }
        return left.token.symbol.localeCompare(right.token.symbol);
    }),
})));
function normalizeAddress(value) {
    return value.toLowerCase();
}
function tokenKey(chainId, address) {
    return `${chainId}:${normalizeAddress(address)}`;
}
function sourceTokenForRecord(record) {
    return (sourceChainTokens(record.sourceChainId).find((token) => token.address.toLowerCase() === record.sourceTokenAddress.toLowerCase()) ?? null);
}
function destinationTokenForRecord(record) {
    const sourceToken = sourceTokenForRecord(record);
    if (sourceToken) {
        return destinationTokenForSource(sourceToken, record.destinationChainId);
    }
    if (normalizeAddress(record.sourceTokenAddress) === ZERO_ADDRESS) {
        return (sourceChainTokens(record.destinationChainId).find((token) => token.isNative) ?? null);
    }
    return null;
}
function formatTokenAmount(value, token) {
    return formatUnits(value, token.decimals, 4);
}
function buildMovementTotals(records) {
    const totalsByKey = new Map();
    function ensureTotals(key) {
        const existingTotals = totalsByKey.get(key);
        if (existingTotals) {
            return existingTotals;
        }
        const nextTotals = { sent: 0n, received: 0n, waiting: 0n };
        totalsByKey.set(key, nextTotals);
        return nextTotals;
    }
    for (const record of records) {
        if (record.walletIsSender) {
            const sourceKey = tokenKey(record.sourceChainId, record.sourceTokenAddress);
            ensureTotals(sourceKey).sent += record.amount;
        }
        if (!record.walletIsRecipient) {
            continue;
        }
        const destinationToken = destinationTokenForRecord(record);
        if (!destinationToken) {
            continue;
        }
        const destinationKey = tokenKey(destinationToken.chainId, destinationToken.address);
        const totals = ensureTotals(destinationKey);
        if (record.claimTransactionHash) {
            totals.received += record.amount;
        }
        else {
            totals.waiting += record.amount;
        }
    }
    return totalsByKey;
}
async function refreshWalletData() {
    if (!swapStore.walletAddress) {
        balanceRows.value = [];
        transferRecords.value = [];
        errorMessage.value = "";
        loading.value = false;
        lastSyncedAt.value = null;
        return;
    }
    loading.value = true;
    errorMessage.value = "";
    try {
        const trackedTokens = SUPPORTED_CHAINS.flatMap((chain) => sourceChainTokens(chain.id));
        const [balances, records] = await Promise.all([
            Promise.all(trackedTokens.map(async (token) => ({
                token,
                balance: await swapStore.readBalanceForToken(token),
            }))),
            fetchTransferRecords(swapStore.walletAddress, {
                limit: 100,
                attestationLimit: 300,
                includeRuntimeState: false,
            }),
        ]);
        transferRecords.value = records;
        const movementByKey = buildMovementTotals(records);
        balanceRows.value = balances.map(({ token, balance }) => {
            const totals = movementByKey.get(tokenKey(token.chainId, token.address)) ?? {
                sent: 0n,
                received: 0n,
                waiting: 0n,
            };
            return {
                token,
                balance,
                sent: totals.sent,
                received: totals.received,
                waiting: totals.waiting,
            };
        });
        lastSyncedAt.value = Math.floor(Date.now() / 1000);
    }
    catch (error) {
        errorMessage.value = error instanceof Error ? error.message : String(error);
    }
    finally {
        loading.value = false;
    }
}
watch(() => swapStore.walletAddress, async () => {
    await refreshWalletData();
});
watch(() => swapStore.lastTxHash, async () => {
    await refreshWalletData();
});
onMounted(async () => {
    await refreshWalletData();
    refreshTimer = window.setInterval(async () => {
        await refreshWalletData();
    }, 5000);
});
onUnmounted(() => {
    if (refreshTimer !== null) {
        window.clearInterval(refreshTimer);
    }
});
const __VLS_ctx = {
    ...{},
    ...{},
};
let __VLS_components;
let __VLS_intrinsics;
let __VLS_directives;
__VLS_asFunctionalElement1(__VLS_intrinsics.section, __VLS_intrinsics.section)({
    ...{ class: "overflow-hidden rounded-[28px] border border-white/10 bg-white/[0.045] shadow-[0_24px_90px_rgba(0,0,0,0.28)] backdrop-blur-xl" },
});
/** @type {__VLS_StyleScopedClasses['overflow-hidden']} */ ;
/** @type {__VLS_StyleScopedClasses['rounded-[28px]']} */ ;
/** @type {__VLS_StyleScopedClasses['border']} */ ;
/** @type {__VLS_StyleScopedClasses['border-white/10']} */ ;
/** @type {__VLS_StyleScopedClasses['bg-white/[0.045]']} */ ;
/** @type {__VLS_StyleScopedClasses['shadow-[0_24px_90px_rgba(0,0,0,0.28)]']} */ ;
/** @type {__VLS_StyleScopedClasses['backdrop-blur-xl']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "border-b border-white/8 px-5 py-4 sm:px-6" },
});
/** @type {__VLS_StyleScopedClasses['border-b']} */ ;
/** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
/** @type {__VLS_StyleScopedClasses['px-5']} */ ;
/** @type {__VLS_StyleScopedClasses['py-4']} */ ;
/** @type {__VLS_StyleScopedClasses['sm:px-6']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between" },
});
/** @type {__VLS_StyleScopedClasses['flex']} */ ;
/** @type {__VLS_StyleScopedClasses['flex-col']} */ ;
/** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
/** @type {__VLS_StyleScopedClasses['lg:flex-row']} */ ;
/** @type {__VLS_StyleScopedClasses['lg:items-end']} */ ;
/** @type {__VLS_StyleScopedClasses['lg:justify-between']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "text-xs uppercase tracking-[0.28em] text-white/45" },
});
/** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
/** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
/** @type {__VLS_StyleScopedClasses['tracking-[0.28em]']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.h2, __VLS_intrinsics.h2)({
    ...{ class: "mt-2 font-display text-2xl font-semibold text-white" },
});
/** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
/** @type {__VLS_StyleScopedClasses['font-display']} */ ;
/** @type {__VLS_StyleScopedClasses['text-2xl']} */ ;
/** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-1 text-sm text-white/55" },
});
/** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
/** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/55']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "rounded-full border border-white/10 bg-white/5 px-3 py-2 text-xs text-white/55" },
});
/** @type {__VLS_StyleScopedClasses['rounded-full']} */ ;
/** @type {__VLS_StyleScopedClasses['border']} */ ;
/** @type {__VLS_StyleScopedClasses['border-white/10']} */ ;
/** @type {__VLS_StyleScopedClasses['bg-white/5']} */ ;
/** @type {__VLS_StyleScopedClasses['px-3']} */ ;
/** @type {__VLS_StyleScopedClasses['py-2']} */ ;
/** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/55']} */ ;
if (__VLS_ctx.lastSyncedAt) {
    __VLS_asFunctionalElement1(__VLS_intrinsics.span, __VLS_intrinsics.span)({});
    (__VLS_ctx.formatTimestamp(__VLS_ctx.lastSyncedAt));
}
else {
    __VLS_asFunctionalElement1(__VLS_intrinsics.span, __VLS_intrinsics.span)({});
}
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "px-5 py-5 sm:px-6" },
});
/** @type {__VLS_StyleScopedClasses['px-5']} */ ;
/** @type {__VLS_StyleScopedClasses['py-5']} */ ;
/** @type {__VLS_StyleScopedClasses['sm:px-6']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "mb-4 grid gap-3 lg:grid-cols-[minmax(0,1fr)_180px_180px_180px]" },
});
/** @type {__VLS_StyleScopedClasses['mb-4']} */ ;
/** @type {__VLS_StyleScopedClasses['grid']} */ ;
/** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
/** @type {__VLS_StyleScopedClasses['lg:grid-cols-[minmax(0,1fr)_180px_180px_180px]']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "rounded-3xl border border-white/8 bg-black/25 p-4" },
});
/** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
/** @type {__VLS_StyleScopedClasses['border']} */ ;
/** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
/** @type {__VLS_StyleScopedClasses['bg-black/25']} */ ;
/** @type {__VLS_StyleScopedClasses['p-4']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "text-[11px] uppercase tracking-[0.22em] text-white/38" },
});
/** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
/** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
/** @type {__VLS_StyleScopedClasses['tracking-[0.22em]']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/38']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-2 font-mono text-sm text-white/80" },
});
/** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
/** @type {__VLS_StyleScopedClasses['font-mono']} */ ;
/** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/80']} */ ;
(__VLS_ctx.walletLabel);
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-1 text-xs text-white/45" },
});
/** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
/** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "rounded-3xl border border-white/8 bg-black/25 p-4" },
});
/** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
/** @type {__VLS_StyleScopedClasses['border']} */ ;
/** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
/** @type {__VLS_StyleScopedClasses['bg-black/25']} */ ;
/** @type {__VLS_StyleScopedClasses['p-4']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "text-[11px] uppercase tracking-[0.22em] text-white/38" },
});
/** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
/** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
/** @type {__VLS_StyleScopedClasses['tracking-[0.22em]']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/38']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-2 font-display text-3xl font-semibold text-rose-200" },
});
/** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
/** @type {__VLS_StyleScopedClasses['font-display']} */ ;
/** @type {__VLS_StyleScopedClasses['text-3xl']} */ ;
/** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
/** @type {__VLS_StyleScopedClasses['text-rose-200']} */ ;
(__VLS_ctx.sentTransferCount);
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-1 text-xs text-white/45" },
});
/** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
/** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "rounded-3xl border border-white/8 bg-black/25 p-4" },
});
/** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
/** @type {__VLS_StyleScopedClasses['border']} */ ;
/** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
/** @type {__VLS_StyleScopedClasses['bg-black/25']} */ ;
/** @type {__VLS_StyleScopedClasses['p-4']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "text-[11px] uppercase tracking-[0.22em] text-white/38" },
});
/** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
/** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
/** @type {__VLS_StyleScopedClasses['tracking-[0.22em]']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/38']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-2 font-display text-3xl font-semibold text-emerald-200" },
});
/** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
/** @type {__VLS_StyleScopedClasses['font-display']} */ ;
/** @type {__VLS_StyleScopedClasses['text-3xl']} */ ;
/** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
/** @type {__VLS_StyleScopedClasses['text-emerald-200']} */ ;
(__VLS_ctx.receivedTransferCount);
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-1 text-xs text-white/45" },
});
/** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
/** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "rounded-3xl border border-white/8 bg-black/25 p-4" },
});
/** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
/** @type {__VLS_StyleScopedClasses['border']} */ ;
/** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
/** @type {__VLS_StyleScopedClasses['bg-black/25']} */ ;
/** @type {__VLS_StyleScopedClasses['p-4']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "text-[11px] uppercase tracking-[0.22em] text-white/38" },
});
/** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
/** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
/** @type {__VLS_StyleScopedClasses['tracking-[0.22em]']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/38']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-2 font-display text-3xl font-semibold text-cyan-100" },
});
/** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
/** @type {__VLS_StyleScopedClasses['font-display']} */ ;
/** @type {__VLS_StyleScopedClasses['text-3xl']} */ ;
/** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
/** @type {__VLS_StyleScopedClasses['text-cyan-100']} */ ;
(__VLS_ctx.waitingTransferCount);
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-1 text-xs text-white/45" },
});
/** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
/** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
if (!__VLS_ctx.swapStore.walletConnected) {
    __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
        ...{ class: "rounded-3xl border border-dashed border-white/12 bg-black/20 px-6 py-12 text-center" },
    });
    /** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
    /** @type {__VLS_StyleScopedClasses['border']} */ ;
    /** @type {__VLS_StyleScopedClasses['border-dashed']} */ ;
    /** @type {__VLS_StyleScopedClasses['border-white/12']} */ ;
    /** @type {__VLS_StyleScopedClasses['bg-black/20']} */ ;
    /** @type {__VLS_StyleScopedClasses['px-6']} */ ;
    /** @type {__VLS_StyleScopedClasses['py-12']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-center']} */ ;
    __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
        ...{ class: "font-display text-xl font-semibold text-white" },
    });
    /** @type {__VLS_StyleScopedClasses['font-display']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-xl']} */ ;
    /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-white']} */ ;
    __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
        ...{ class: "mt-2 text-sm text-white/45" },
    });
    /** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
}
else if (__VLS_ctx.loading && __VLS_ctx.balanceRows.length === 0) {
    __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
        ...{ class: "grid gap-4 xl:grid-cols-2" },
    });
    /** @type {__VLS_StyleScopedClasses['grid']} */ ;
    /** @type {__VLS_StyleScopedClasses['gap-4']} */ ;
    /** @type {__VLS_StyleScopedClasses['xl:grid-cols-2']} */ ;
    for (const [index] of __VLS_vFor((2))) {
        __VLS_asFunctionalElement1(__VLS_intrinsics.div)({
            key: (index),
            ...{ class: "h-60 animate-pulse rounded-3xl border border-white/8 bg-white/5" },
        });
        /** @type {__VLS_StyleScopedClasses['h-60']} */ ;
        /** @type {__VLS_StyleScopedClasses['animate-pulse']} */ ;
        /** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
        /** @type {__VLS_StyleScopedClasses['border']} */ ;
        /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
        /** @type {__VLS_StyleScopedClasses['bg-white/5']} */ ;
        // @ts-ignore
        [lastSyncedAt, lastSyncedAt, formatTimestamp, walletLabel, sentTransferCount, receivedTransferCount, waitingTransferCount, swapStore, loading, balanceRows,];
    }
}
else if (__VLS_ctx.errorMessage) {
    __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
        ...{ class: "rounded-3xl border border-rose-500/20 bg-rose-500/10 px-4 py-4 text-sm text-rose-100" },
    });
    /** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
    /** @type {__VLS_StyleScopedClasses['border']} */ ;
    /** @type {__VLS_StyleScopedClasses['border-rose-500/20']} */ ;
    /** @type {__VLS_StyleScopedClasses['bg-rose-500/10']} */ ;
    /** @type {__VLS_StyleScopedClasses['px-4']} */ ;
    /** @type {__VLS_StyleScopedClasses['py-4']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-rose-100']} */ ;
    (__VLS_ctx.errorMessage);
}
else {
    __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
        ...{ class: "grid gap-4 xl:grid-cols-2" },
    });
    /** @type {__VLS_StyleScopedClasses['grid']} */ ;
    /** @type {__VLS_StyleScopedClasses['gap-4']} */ ;
    /** @type {__VLS_StyleScopedClasses['xl:grid-cols-2']} */ ;
    for (const [section] of __VLS_vFor((__VLS_ctx.chainSections))) {
        __VLS_asFunctionalElement1(__VLS_intrinsics.article, __VLS_intrinsics.article)({
            key: (section.chainId),
            ...{ class: "rounded-3xl border border-white/8 bg-black/25 p-4" },
        });
        /** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
        /** @type {__VLS_StyleScopedClasses['border']} */ ;
        /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
        /** @type {__VLS_StyleScopedClasses['bg-black/25']} */ ;
        /** @type {__VLS_StyleScopedClasses['p-4']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
            ...{ class: "flex flex-col gap-3 border-b border-white/8 pb-4 sm:flex-row sm:items-start sm:justify-between" },
        });
        /** @type {__VLS_StyleScopedClasses['flex']} */ ;
        /** @type {__VLS_StyleScopedClasses['flex-col']} */ ;
        /** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
        /** @type {__VLS_StyleScopedClasses['border-b']} */ ;
        /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
        /** @type {__VLS_StyleScopedClasses['pb-4']} */ ;
        /** @type {__VLS_StyleScopedClasses['sm:flex-row']} */ ;
        /** @type {__VLS_StyleScopedClasses['sm:items-start']} */ ;
        /** @type {__VLS_StyleScopedClasses['sm:justify-between']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "font-display text-2xl font-semibold text-white" },
        });
        /** @type {__VLS_StyleScopedClasses['font-display']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-2xl']} */ ;
        /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white']} */ ;
        (section.chainLabel);
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "mt-1 text-sm text-white/45" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
            ...{ class: "flex flex-wrap gap-2 text-[11px] uppercase tracking-[0.18em]" },
        });
        /** @type {__VLS_StyleScopedClasses['flex']} */ ;
        /** @type {__VLS_StyleScopedClasses['flex-wrap']} */ ;
        /** @type {__VLS_StyleScopedClasses['gap-2']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
        /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
        /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
        if (__VLS_ctx.swapStore.walletChainId === section.chainId) {
            __VLS_asFunctionalElement1(__VLS_intrinsics.span, __VLS_intrinsics.span)({
                ...{ class: "rounded-full border border-cyan-300/25 bg-cyan-300/10 px-2.5 py-1 text-cyan-50" },
            });
            /** @type {__VLS_StyleScopedClasses['rounded-full']} */ ;
            /** @type {__VLS_StyleScopedClasses['border']} */ ;
            /** @type {__VLS_StyleScopedClasses['border-cyan-300/25']} */ ;
            /** @type {__VLS_StyleScopedClasses['bg-cyan-300/10']} */ ;
            /** @type {__VLS_StyleScopedClasses['px-2.5']} */ ;
            /** @type {__VLS_StyleScopedClasses['py-1']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-cyan-50']} */ ;
        }
        if (__VLS_ctx.swapStore.selectedChainId === section.chainId) {
            __VLS_asFunctionalElement1(__VLS_intrinsics.span, __VLS_intrinsics.span)({
                ...{ class: "rounded-full border border-white/10 bg-white/5 px-2.5 py-1 text-white/65" },
            });
            /** @type {__VLS_StyleScopedClasses['rounded-full']} */ ;
            /** @type {__VLS_StyleScopedClasses['border']} */ ;
            /** @type {__VLS_StyleScopedClasses['border-white/10']} */ ;
            /** @type {__VLS_StyleScopedClasses['bg-white/5']} */ ;
            /** @type {__VLS_StyleScopedClasses['px-2.5']} */ ;
            /** @type {__VLS_StyleScopedClasses['py-1']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-white/65']} */ ;
        }
        if (section.rows.length === 0) {
            __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                ...{ class: "pt-4 text-sm text-white/45" },
            });
            /** @type {__VLS_StyleScopedClasses['pt-4']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
        }
        else {
            __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                ...{ class: "mt-4 space-y-3" },
            });
            /** @type {__VLS_StyleScopedClasses['mt-4']} */ ;
            /** @type {__VLS_StyleScopedClasses['space-y-3']} */ ;
            for (const [row] of __VLS_vFor((section.rows))) {
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                    key: (`${row.token.chainId}:${row.token.address}`),
                    ...{ class: "rounded-3xl border border-white/8 bg-white/[0.03] p-4" },
                });
                /** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
                /** @type {__VLS_StyleScopedClasses['border']} */ ;
                /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
                /** @type {__VLS_StyleScopedClasses['bg-white/[0.03]']} */ ;
                /** @type {__VLS_StyleScopedClasses['p-4']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                    ...{ class: "flex flex-col gap-4" },
                });
                /** @type {__VLS_StyleScopedClasses['flex']} */ ;
                /** @type {__VLS_StyleScopedClasses['flex-col']} */ ;
                /** @type {__VLS_StyleScopedClasses['gap-4']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                    ...{ class: "flex flex-wrap items-center gap-2" },
                });
                /** @type {__VLS_StyleScopedClasses['flex']} */ ;
                /** @type {__VLS_StyleScopedClasses['flex-wrap']} */ ;
                /** @type {__VLS_StyleScopedClasses['items-center']} */ ;
                /** @type {__VLS_StyleScopedClasses['gap-2']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "text-sm font-semibold text-white" },
                });
                /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
                /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white']} */ ;
                (row.token.symbol);
                __VLS_asFunctionalElement1(__VLS_intrinsics.span, __VLS_intrinsics.span)({
                    ...{ class: "rounded-full border border-white/10 bg-white/5 px-2 py-0.5 text-[10px] uppercase tracking-[0.18em] text-white/45" },
                });
                /** @type {__VLS_StyleScopedClasses['rounded-full']} */ ;
                /** @type {__VLS_StyleScopedClasses['border']} */ ;
                /** @type {__VLS_StyleScopedClasses['border-white/10']} */ ;
                /** @type {__VLS_StyleScopedClasses['bg-white/5']} */ ;
                /** @type {__VLS_StyleScopedClasses['px-2']} */ ;
                /** @type {__VLS_StyleScopedClasses['py-0.5']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-[10px]']} */ ;
                /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
                /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
                (row.token.isNative ? 'native' : 'token');
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "mt-1 text-xs text-white/45" },
                });
                /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
                (row.token.name);
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                    ...{ class: "grid gap-3 sm:grid-cols-2 xl:grid-cols-4" },
                });
                /** @type {__VLS_StyleScopedClasses['grid']} */ ;
                /** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
                /** @type {__VLS_StyleScopedClasses['sm:grid-cols-2']} */ ;
                /** @type {__VLS_StyleScopedClasses['xl:grid-cols-4']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                    ...{ class: "rounded-2xl border border-white/8 bg-black/20 px-3 py-3" },
                });
                /** @type {__VLS_StyleScopedClasses['rounded-2xl']} */ ;
                /** @type {__VLS_StyleScopedClasses['border']} */ ;
                /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
                /** @type {__VLS_StyleScopedClasses['bg-black/20']} */ ;
                /** @type {__VLS_StyleScopedClasses['px-3']} */ ;
                /** @type {__VLS_StyleScopedClasses['py-3']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
                });
                /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
                /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
                /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "mt-1 text-lg font-semibold text-white" },
                });
                /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-lg']} */ ;
                /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white']} */ ;
                (__VLS_ctx.formatTokenAmount(row.balance, row.token));
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                    ...{ class: "rounded-2xl border border-white/8 bg-black/20 px-3 py-3" },
                });
                /** @type {__VLS_StyleScopedClasses['rounded-2xl']} */ ;
                /** @type {__VLS_StyleScopedClasses['border']} */ ;
                /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
                /** @type {__VLS_StyleScopedClasses['bg-black/20']} */ ;
                /** @type {__VLS_StyleScopedClasses['px-3']} */ ;
                /** @type {__VLS_StyleScopedClasses['py-3']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
                });
                /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
                /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
                /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "mt-1 text-lg font-semibold text-rose-200" },
                });
                /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-lg']} */ ;
                /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-rose-200']} */ ;
                (__VLS_ctx.formatTokenAmount(row.sent, row.token));
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                    ...{ class: "rounded-2xl border border-white/8 bg-black/20 px-3 py-3" },
                });
                /** @type {__VLS_StyleScopedClasses['rounded-2xl']} */ ;
                /** @type {__VLS_StyleScopedClasses['border']} */ ;
                /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
                /** @type {__VLS_StyleScopedClasses['bg-black/20']} */ ;
                /** @type {__VLS_StyleScopedClasses['px-3']} */ ;
                /** @type {__VLS_StyleScopedClasses['py-3']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
                });
                /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
                /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
                /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "mt-1 text-lg font-semibold text-emerald-200" },
                });
                /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-lg']} */ ;
                /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-emerald-200']} */ ;
                (__VLS_ctx.formatTokenAmount(row.received, row.token));
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                    ...{ class: "rounded-2xl border border-white/8 bg-black/20 px-3 py-3" },
                });
                /** @type {__VLS_StyleScopedClasses['rounded-2xl']} */ ;
                /** @type {__VLS_StyleScopedClasses['border']} */ ;
                /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
                /** @type {__VLS_StyleScopedClasses['bg-black/20']} */ ;
                /** @type {__VLS_StyleScopedClasses['px-3']} */ ;
                /** @type {__VLS_StyleScopedClasses['py-3']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
                });
                /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
                /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
                /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "mt-1 text-lg font-semibold text-cyan-100" },
                });
                /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-lg']} */ ;
                /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-cyan-100']} */ ;
                (__VLS_ctx.formatTokenAmount(row.waiting, row.token));
                // @ts-ignore
                [swapStore, swapStore, errorMessage, errorMessage, chainSections, formatTokenAmount, formatTokenAmount, formatTokenAmount, formatTokenAmount,];
            }
        }
        // @ts-ignore
        [];
    }
}
// @ts-ignore
[];
const __VLS_export = (await import('vue')).defineComponent({});
export default {};
