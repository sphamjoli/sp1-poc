import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { useSwapStore } from "@/stores/swap";
import { claimBridgeTransfer } from "@/services/bridge";
import { fetchTransferRecords, markTransferRecordReceived, } from "@/services/transfers";
import { formatDuration, formatTimestamp, shortenAddress } from "@/utils/format";
import { formatUnits } from "@/utils/amount";
const LOCAL_CLAIMS_STORAGE_KEY = "bridge:local-claims";
const swapStore = useSwapStore();
const transferRecords = ref([]);
const loading = ref(false);
const errorMessage = ref("");
const claimErrorMessage = ref("");
const refreshedAt = ref(null);
const activeFilter = ref("all");
const claimingTransferId = ref(null);
const localClaims = ref(readStoredLocalClaims());
const nowSeconds = ref(Math.floor(Date.now() / 1000));
const claimStartedAt = ref(null);
let refreshTimer = null;
let elapsedTimer = null;
const displayedTransfers = computed(() => transferRecords.value.map((record) => {
    if (record.claimTransactionHash) {
        return record;
    }
    const localClaim = localClaims.value[record.id];
    if (!localClaim) {
        return record;
    }
    const connectedWallet = swapStore.walletAddress?.toLowerCase() ?? null;
    if (connectedWallet && connectedWallet !== localClaim.walletAddress) {
        return record;
    }
    return markTransferRecordReceived(record, localClaim.claimTimestamp, localClaim.claimTransactionHash);
}));
const readyTransfers = computed(() => displayedTransfers.value.filter((record) => record.state === "claimable"));
const completedTransfers = computed(() => displayedTransfers.value.filter((record) => record.state === "complete"));
const inProgressTransfers = computed(() => displayedTransfers.value.filter((record) => record.state === "attesting" || record.state === "pending"));
const averageSettlementSeconds = computed(() => {
    if (completedTransfers.value.length === 0) {
        return null;
    }
    const total = completedTransfers.value.reduce((sum, record) => sum + record.durationSeconds, 0);
    return Math.round(total / completedTransfers.value.length);
});
const activityTabs = computed(() => [
    {
        id: "all",
        label: "All transfers",
        count: transferRecords.value.length,
    },
    {
        id: "action",
        label: "Ready to receive",
        count: readyTransfers.value.length,
    },
    {
        id: "progress",
        label: "In progress",
        count: inProgressTransfers.value.length,
    },
    {
        id: "done",
        label: "Received",
        count: completedTransfers.value.length,
    },
]);
const visibleTransfers = computed(() => {
    switch (activeFilter.value) {
        case "action":
            return readyTransfers.value;
        case "progress":
            return inProgressTransfers.value;
        case "done":
            return completedTransfers.value;
        default:
            return displayedTransfers.value;
    }
});
const claimElapsedSeconds = computed(() => claimStartedAt.value === null ? 0 : nowSeconds.value - claimStartedAt.value);
function readStoredLocalClaims() {
    if (typeof window === "undefined") {
        return {};
    }
    try {
        const rawValue = window.localStorage.getItem(LOCAL_CLAIMS_STORAGE_KEY);
        if (!rawValue) {
            return {};
        }
        const parsedValue = JSON.parse(rawValue);
        return parsedValue && typeof parsedValue === "object" ? parsedValue : {};
    }
    catch {
        return {};
    }
}
function writeStoredLocalClaims(nextClaims) {
    if (typeof window === "undefined") {
        return;
    }
    window.localStorage.setItem(LOCAL_CLAIMS_STORAGE_KEY, JSON.stringify(nextClaims));
}
function setLocalClaimState(record, walletAddress, claimTransactionHash, claimTimestamp) {
    const nextClaims = {
        ...localClaims.value,
        [record.id]: {
            walletAddress: walletAddress.toLowerCase(),
            claimTransactionHash,
            claimTimestamp,
        },
    };
    localClaims.value = nextClaims;
    writeStoredLocalClaims(nextClaims);
}
function clearSyncedLocalClaims(records) {
    const syncedIds = new Set(records.filter((record) => Boolean(record.claimTransactionHash)).map((record) => record.id));
    if (syncedIds.size === 0) {
        return;
    }
    const nextClaims = Object.fromEntries(Object.entries(localClaims.value).filter(([recordId]) => !syncedIds.has(recordId)));
    localClaims.value = nextClaims;
    writeStoredLocalClaims(nextClaims);
}
function isAlreadyClaimedError(error) {
    const message = error instanceof Error ? error.message : String(error);
    const normalizedMessage = message.toLowerCase();
    return normalizedMessage.includes("alreadyclaimed") || normalizedMessage.includes("already claimed");
}
function stateBadgeClass(state) {
    if (state === "complete") {
        return "bg-emerald-400/15 text-emerald-200";
    }
    if (state === "claimable") {
        return "bg-cyan-300/15 text-cyan-100";
    }
    if (state === "attesting") {
        return "bg-amber-400/15 text-amber-100";
    }
    return "bg-white/8 text-white/60";
}
function progressWidth(state) {
    if (state === "complete") {
        return "100%";
    }
    if (state === "claimable") {
        return "84%";
    }
    if (state === "attesting") {
        return "58%";
    }
    return "24%";
}
function outgoingBalanceLabel(record) {
    return `-${formatUnits(record.amount, record.assetDecimals, 4)} ${record.assetSymbol}`;
}
function incomingBalanceLabel(record) {
    return `+${formatUnits(record.amount, record.assetDecimals, 4)} ${record.assetSymbol}`;
}
function incomingBalanceNote(record) {
    if (record.state === "complete") {
        return `Received on ${record.destinationChainLabel}.`;
    }
    if (record.state === "claimable") {
        return `Ready to receive on ${record.destinationChainLabel} now.`;
    }
    if (record.state === "attesting") {
        return `Will arrive on ${record.destinationChainLabel} after checks finish.`;
    }
    return `Waiting for the first checks on ${record.destinationChainLabel}.`;
}
function claimButtonLabel(record) {
    if (claimingTransferId.value === record.id) {
        return "Receiving";
    }
    if (swapStore.walletChainId === record.destinationChainId) {
        return "Receive funds";
    }
    return `Switch to ${record.destinationChainLabel} and receive`;
}
async function refreshTransferRecords() {
    if (!swapStore.walletAddress) {
        transferRecords.value = [];
        loading.value = false;
        errorMessage.value = "";
        claimErrorMessage.value = "";
        refreshedAt.value = null;
        return;
    }
    loading.value = true;
    errorMessage.value = "";
    try {
        transferRecords.value = await fetchTransferRecords(swapStore.walletAddress, {
            limit: 50,
            attestationLimit: 300,
        });
        clearSyncedLocalClaims(transferRecords.value);
        refreshedAt.value = Math.floor(Date.now() / 1000);
    }
    catch (error) {
        errorMessage.value = error instanceof Error ? error.message : String(error);
    }
    finally {
        loading.value = false;
    }
}
async function receiveTransfer(record) {
    if (!swapStore.walletAddress || !swapStore.activeWallet) {
        claimErrorMessage.value = "Connect the receiving wallet first.";
        return;
    }
    claimErrorMessage.value = "";
    claimingTransferId.value = record.id;
    claimStartedAt.value = Math.floor(Date.now() / 1000);
    try {
        if (swapStore.walletChainId !== record.destinationChainId) {
            await swapStore.switchWalletToChain(record.destinationChainId);
        }
        const receipt = await claimBridgeTransfer(swapStore.activeWallet.provider, swapStore.walletAddress, record);
        const claimTimestamp = Math.floor(Date.now() / 1000);
        setLocalClaimState(record, swapStore.walletAddress, receipt.txHash, claimTimestamp);
        transferRecords.value = transferRecords.value.map((entry) => entry.id === record.id
            ? markTransferRecordReceived(entry, claimTimestamp, receipt.txHash)
            : entry);
        swapStore.lastTxHash = receipt.txHash;
        swapStore.statusMessage = "Funds received. Balances and transfer progress are updating.";
        await Promise.all([swapStore.refreshBalances(), refreshTransferRecords()]);
    }
    catch (error) {
        if (isAlreadyClaimedError(error) && swapStore.walletAddress) {
            const claimTimestamp = Math.floor(Date.now() / 1000);
            setLocalClaimState(record, swapStore.walletAddress, record.claimTransactionHash, claimTimestamp);
            transferRecords.value = transferRecords.value.map((entry) => entry.id === record.id
                ? markTransferRecordReceived(entry, claimTimestamp, entry.claimTransactionHash)
                : entry);
            claimErrorMessage.value = "";
            swapStore.statusMessage = "Funds were already received. Waiting for activity sync.";
            await Promise.all([swapStore.refreshBalances(), refreshTransferRecords()]);
            return;
        }
        claimErrorMessage.value = error instanceof Error ? error.message : String(error);
    }
    finally {
        claimingTransferId.value = null;
        claimStartedAt.value = null;
    }
}
watch(() => swapStore.walletAddress, async () => {
    await refreshTransferRecords();
});
watch(() => swapStore.lastTxHash, async () => {
    await refreshTransferRecords();
});
onMounted(async () => {
    await refreshTransferRecords();
    refreshTimer = window.setInterval(async () => {
        await refreshTransferRecords();
    }, 5000);
    elapsedTimer = window.setInterval(() => {
        nowSeconds.value = Math.floor(Date.now() / 1000);
    }, 1000);
});
onUnmounted(() => {
    if (refreshTimer !== null) {
        window.clearInterval(refreshTimer);
    }
    if (elapsedTimer !== null) {
        window.clearInterval(elapsedTimer);
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
    ...{ class: "overflow-hidden rounded-[32px] border border-white/10 bg-white/[0.045] shadow-[0_32px_120px_rgba(0,0,0,0.34)] backdrop-blur-xl" },
});
/** @type {__VLS_StyleScopedClasses['overflow-hidden']} */ ;
/** @type {__VLS_StyleScopedClasses['rounded-[32px]']} */ ;
/** @type {__VLS_StyleScopedClasses['border']} */ ;
/** @type {__VLS_StyleScopedClasses['border-white/10']} */ ;
/** @type {__VLS_StyleScopedClasses['bg-white/[0.045]']} */ ;
/** @type {__VLS_StyleScopedClasses['shadow-[0_32px_120px_rgba(0,0,0,0.34)]']} */ ;
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
    ...{ class: "flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between" },
});
/** @type {__VLS_StyleScopedClasses['flex']} */ ;
/** @type {__VLS_StyleScopedClasses['flex-col']} */ ;
/** @type {__VLS_StyleScopedClasses['gap-4']} */ ;
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
    ...{ class: "grid grid-cols-2 gap-3 sm:grid-cols-4" },
});
/** @type {__VLS_StyleScopedClasses['grid']} */ ;
/** @type {__VLS_StyleScopedClasses['grid-cols-2']} */ ;
/** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
/** @type {__VLS_StyleScopedClasses['sm:grid-cols-4']} */ ;
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
    ...{ class: "text-[11px] uppercase tracking-[0.2em] text-white/40" },
});
/** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
/** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
/** @type {__VLS_StyleScopedClasses['tracking-[0.2em]']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/40']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-2 text-xl font-semibold text-cyan-100" },
});
/** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
/** @type {__VLS_StyleScopedClasses['text-xl']} */ ;
/** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
/** @type {__VLS_StyleScopedClasses['text-cyan-100']} */ ;
(__VLS_ctx.readyTransfers.length);
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
    ...{ class: "text-[11px] uppercase tracking-[0.2em] text-white/40" },
});
/** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
/** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
/** @type {__VLS_StyleScopedClasses['tracking-[0.2em]']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/40']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-2 text-xl font-semibold text-white" },
});
/** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
/** @type {__VLS_StyleScopedClasses['text-xl']} */ ;
/** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white']} */ ;
(__VLS_ctx.inProgressTransfers.length);
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
    ...{ class: "text-[11px] uppercase tracking-[0.2em] text-white/40" },
});
/** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
/** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
/** @type {__VLS_StyleScopedClasses['tracking-[0.2em]']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/40']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-2 text-xl font-semibold text-emerald-200" },
});
/** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
/** @type {__VLS_StyleScopedClasses['text-xl']} */ ;
/** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
/** @type {__VLS_StyleScopedClasses['text-emerald-200']} */ ;
(__VLS_ctx.completedTransfers.length);
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
    ...{ class: "text-[11px] uppercase tracking-[0.2em] text-white/40" },
});
/** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
/** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
/** @type {__VLS_StyleScopedClasses['tracking-[0.2em]']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/40']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
    ...{ class: "mt-2 text-xl font-semibold text-white" },
});
/** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
/** @type {__VLS_StyleScopedClasses['text-xl']} */ ;
/** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white']} */ ;
(__VLS_ctx.averageSettlementSeconds ? __VLS_ctx.formatDuration(__VLS_ctx.averageSettlementSeconds) : '-');
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "px-5 py-5 sm:px-6" },
});
/** @type {__VLS_StyleScopedClasses['px-5']} */ ;
/** @type {__VLS_StyleScopedClasses['py-5']} */ ;
/** @type {__VLS_StyleScopedClasses['sm:px-6']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "mb-4 flex flex-col gap-3 md:flex-row md:items-center md:justify-between" },
});
/** @type {__VLS_StyleScopedClasses['mb-4']} */ ;
/** @type {__VLS_StyleScopedClasses['flex']} */ ;
/** @type {__VLS_StyleScopedClasses['flex-col']} */ ;
/** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
/** @type {__VLS_StyleScopedClasses['md:flex-row']} */ ;
/** @type {__VLS_StyleScopedClasses['md:items-center']} */ ;
/** @type {__VLS_StyleScopedClasses['md:justify-between']} */ ;
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "flex flex-wrap gap-2" },
});
/** @type {__VLS_StyleScopedClasses['flex']} */ ;
/** @type {__VLS_StyleScopedClasses['flex-wrap']} */ ;
/** @type {__VLS_StyleScopedClasses['gap-2']} */ ;
for (const [tab] of __VLS_vFor((__VLS_ctx.activityTabs))) {
    __VLS_asFunctionalElement1(__VLS_intrinsics.button, __VLS_intrinsics.button)({
        ...{ onClick: (...[$event]) => {
                __VLS_ctx.activeFilter = tab.id;
                // @ts-ignore
                [readyTransfers, inProgressTransfers, completedTransfers, averageSettlementSeconds, averageSettlementSeconds, formatDuration, activityTabs, activeFilter,];
            } },
        key: (tab.id),
        type: "button",
        ...{ class: "rounded-full border px-3 py-2 text-sm transition" },
        ...{ class: (__VLS_ctx.activeFilter === tab.id
                ? 'border-cyan-300/35 bg-cyan-300/10 text-cyan-50'
                : 'border-white/10 bg-white/5 text-white/60 hover:border-white/20 hover:text-white') },
    });
    /** @type {__VLS_StyleScopedClasses['rounded-full']} */ ;
    /** @type {__VLS_StyleScopedClasses['border']} */ ;
    /** @type {__VLS_StyleScopedClasses['px-3']} */ ;
    /** @type {__VLS_StyleScopedClasses['py-2']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
    /** @type {__VLS_StyleScopedClasses['transition']} */ ;
    (tab.label);
    (tab.count);
    // @ts-ignore
    [activeFilter,];
}
__VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
    ...{ class: "flex items-center justify-between gap-3 text-xs text-white/40" },
});
/** @type {__VLS_StyleScopedClasses['flex']} */ ;
/** @type {__VLS_StyleScopedClasses['items-center']} */ ;
/** @type {__VLS_StyleScopedClasses['justify-between']} */ ;
/** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
/** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/40']} */ ;
if (__VLS_ctx.refreshedAt) {
    __VLS_asFunctionalElement1(__VLS_intrinsics.span, __VLS_intrinsics.span)({});
    (__VLS_ctx.formatTimestamp(__VLS_ctx.refreshedAt));
}
else {
    __VLS_asFunctionalElement1(__VLS_intrinsics.span, __VLS_intrinsics.span)({});
}
__VLS_asFunctionalElement1(__VLS_intrinsics.button, __VLS_intrinsics.button)({
    ...{ onClick: (__VLS_ctx.refreshTransferRecords) },
    type: "button",
    ...{ class: "rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-white/65 transition hover:border-cyan-300/30 hover:text-white" },
});
/** @type {__VLS_StyleScopedClasses['rounded-full']} */ ;
/** @type {__VLS_StyleScopedClasses['border']} */ ;
/** @type {__VLS_StyleScopedClasses['border-white/10']} */ ;
/** @type {__VLS_StyleScopedClasses['bg-white/5']} */ ;
/** @type {__VLS_StyleScopedClasses['px-3']} */ ;
/** @type {__VLS_StyleScopedClasses['py-1.5']} */ ;
/** @type {__VLS_StyleScopedClasses['text-white/65']} */ ;
/** @type {__VLS_StyleScopedClasses['transition']} */ ;
/** @type {__VLS_StyleScopedClasses['hover:border-cyan-300/30']} */ ;
/** @type {__VLS_StyleScopedClasses['hover:text-white']} */ ;
if (__VLS_ctx.claimErrorMessage) {
    __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
        ...{ class: "mb-4 rounded-3xl border border-rose-500/20 bg-rose-500/10 px-4 py-4 text-sm text-rose-100" },
    });
    /** @type {__VLS_StyleScopedClasses['mb-4']} */ ;
    /** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
    /** @type {__VLS_StyleScopedClasses['border']} */ ;
    /** @type {__VLS_StyleScopedClasses['border-rose-500/20']} */ ;
    /** @type {__VLS_StyleScopedClasses['bg-rose-500/10']} */ ;
    /** @type {__VLS_StyleScopedClasses['px-4']} */ ;
    /** @type {__VLS_StyleScopedClasses['py-4']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-rose-100']} */ ;
    (__VLS_ctx.claimErrorMessage);
}
if (__VLS_ctx.loading && __VLS_ctx.transferRecords.length === 0) {
    __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
        ...{ class: "space-y-3" },
    });
    /** @type {__VLS_StyleScopedClasses['space-y-3']} */ ;
    for (const [index] of __VLS_vFor((3))) {
        __VLS_asFunctionalElement1(__VLS_intrinsics.div)({
            key: (index),
            ...{ class: "h-40 animate-pulse rounded-3xl border border-white/8 bg-white/5" },
        });
        /** @type {__VLS_StyleScopedClasses['h-40']} */ ;
        /** @type {__VLS_StyleScopedClasses['animate-pulse']} */ ;
        /** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
        /** @type {__VLS_StyleScopedClasses['border']} */ ;
        /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
        /** @type {__VLS_StyleScopedClasses['bg-white/5']} */ ;
        // @ts-ignore
        [refreshedAt, refreshedAt, formatTimestamp, refreshTransferRecords, claimErrorMessage, claimErrorMessage, loading, transferRecords,];
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
else if (__VLS_ctx.transferRecords.length === 0) {
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
    (__VLS_ctx.swapStore.walletConnected ? 'No transfers yet' : 'Wallet connection required');
    __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
        ...{ class: "mt-2 text-sm text-white/45" },
    });
    /** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
    /** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
    (__VLS_ctx.swapStore.walletConnected
        ? 'Transfers will appear here after deposits are indexed for this wallet.'
        : 'Connect a wallet to load transfers and see when funds are ready to receive.');
}
else if (__VLS_ctx.visibleTransfers.length === 0) {
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
else {
    __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
        ...{ class: "space-y-3" },
    });
    /** @type {__VLS_StyleScopedClasses['space-y-3']} */ ;
    for (const [record] of __VLS_vFor((__VLS_ctx.visibleTransfers))) {
        __VLS_asFunctionalElement1(__VLS_intrinsics.article, __VLS_intrinsics.article)({
            key: (record.id),
            ...{ class: "rounded-3xl border border-white/8 bg-black/25 p-4 transition hover:border-cyan-300/25 hover:bg-black/35" },
        });
        /** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
        /** @type {__VLS_StyleScopedClasses['border']} */ ;
        /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
        /** @type {__VLS_StyleScopedClasses['bg-black/25']} */ ;
        /** @type {__VLS_StyleScopedClasses['p-4']} */ ;
        /** @type {__VLS_StyleScopedClasses['transition']} */ ;
        /** @type {__VLS_StyleScopedClasses['hover:border-cyan-300/25']} */ ;
        /** @type {__VLS_StyleScopedClasses['hover:bg-black/35']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
            ...{ class: "flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between" },
        });
        /** @type {__VLS_StyleScopedClasses['flex']} */ ;
        /** @type {__VLS_StyleScopedClasses['flex-col']} */ ;
        /** @type {__VLS_StyleScopedClasses['gap-4']} */ ;
        /** @type {__VLS_StyleScopedClasses['xl:flex-row']} */ ;
        /** @type {__VLS_StyleScopedClasses['xl:items-start']} */ ;
        /** @type {__VLS_StyleScopedClasses['xl:justify-between']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
            ...{ class: "min-w-0 flex-1" },
        });
        /** @type {__VLS_StyleScopedClasses['min-w-0']} */ ;
        /** @type {__VLS_StyleScopedClasses['flex-1']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
            ...{ class: "flex flex-wrap items-center gap-2" },
        });
        /** @type {__VLS_StyleScopedClasses['flex']} */ ;
        /** @type {__VLS_StyleScopedClasses['flex-wrap']} */ ;
        /** @type {__VLS_StyleScopedClasses['items-center']} */ ;
        /** @type {__VLS_StyleScopedClasses['gap-2']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.span, __VLS_intrinsics.span)({
            ...{ class: "rounded-full border border-white/10 bg-white/5 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.24em] text-white/50" },
        });
        /** @type {__VLS_StyleScopedClasses['rounded-full']} */ ;
        /** @type {__VLS_StyleScopedClasses['border']} */ ;
        /** @type {__VLS_StyleScopedClasses['border-white/10']} */ ;
        /** @type {__VLS_StyleScopedClasses['bg-white/5']} */ ;
        /** @type {__VLS_StyleScopedClasses['px-2.5']} */ ;
        /** @type {__VLS_StyleScopedClasses['py-1']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
        /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
        /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
        /** @type {__VLS_StyleScopedClasses['tracking-[0.24em]']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/50']} */ ;
        (record.assetSymbol);
        __VLS_asFunctionalElement1(__VLS_intrinsics.span, __VLS_intrinsics.span)({
            ...{ class: "rounded-full px-3 py-1 text-xs font-semibold" },
            ...{ class: (__VLS_ctx.stateBadgeClass(record.state)) },
        });
        /** @type {__VLS_StyleScopedClasses['rounded-full']} */ ;
        /** @type {__VLS_StyleScopedClasses['px-3']} */ ;
        /** @type {__VLS_StyleScopedClasses['py-1']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
        /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
        (record.stateLabel);
        __VLS_asFunctionalElement1(__VLS_intrinsics.span, __VLS_intrinsics.span)({
            ...{ class: "text-xs text-white/35" },
        });
        /** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
        (__VLS_ctx.formatTimestamp(record.depositTimestamp));
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
            ...{ class: "mt-4 flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-4']} */ ;
        /** @type {__VLS_StyleScopedClasses['flex']} */ ;
        /** @type {__VLS_StyleScopedClasses['flex-col']} */ ;
        /** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
        /** @type {__VLS_StyleScopedClasses['lg:flex-row']} */ ;
        /** @type {__VLS_StyleScopedClasses['lg:items-end']} */ ;
        /** @type {__VLS_StyleScopedClasses['lg:justify-between']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "font-display text-2xl font-semibold text-white" },
        });
        /** @type {__VLS_StyleScopedClasses['font-display']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-2xl']} */ ;
        /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white']} */ ;
        (__VLS_ctx.formatUnits(record.amount, record.assetDecimals, 4));
        (record.assetSymbol);
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "mt-1 text-sm text-white/50" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/50']} */ ;
        (record.sourceChainLabel);
        (record.destinationChainLabel);
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
            ...{ class: "flex flex-wrap gap-4 text-sm text-white/50" },
        });
        /** @type {__VLS_StyleScopedClasses['flex']} */ ;
        /** @type {__VLS_StyleScopedClasses['flex-wrap']} */ ;
        /** @type {__VLS_StyleScopedClasses['gap-4']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/50']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
        });
        /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
        /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
        /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "mt-1 font-semibold text-white" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
        /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white']} */ ;
        (__VLS_ctx.formatDuration(record.durationSeconds));
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
        });
        /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
        /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
        /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "mt-1 font-semibold text-white" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
        /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white']} */ ;
        (record.attestationCount);
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
            ...{ class: "mt-4 h-2 overflow-hidden rounded-full bg-white/8" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-4']} */ ;
        /** @type {__VLS_StyleScopedClasses['h-2']} */ ;
        /** @type {__VLS_StyleScopedClasses['overflow-hidden']} */ ;
        /** @type {__VLS_StyleScopedClasses['rounded-full']} */ ;
        /** @type {__VLS_StyleScopedClasses['bg-white/8']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.div)({
            ...{ class: "h-full rounded-full bg-gradient-to-r from-emerald-400 via-cyan-400 to-amber-300" },
            ...{ style: ({ width: __VLS_ctx.progressWidth(record.state) }) },
        });
        /** @type {__VLS_StyleScopedClasses['h-full']} */ ;
        /** @type {__VLS_StyleScopedClasses['rounded-full']} */ ;
        /** @type {__VLS_StyleScopedClasses['bg-gradient-to-r']} */ ;
        /** @type {__VLS_StyleScopedClasses['from-emerald-400']} */ ;
        /** @type {__VLS_StyleScopedClasses['via-cyan-400']} */ ;
        /** @type {__VLS_StyleScopedClasses['to-amber-300']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
            ...{ class: "mt-4 grid gap-3 text-sm md:grid-cols-2" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-4']} */ ;
        /** @type {__VLS_StyleScopedClasses['grid']} */ ;
        /** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
        /** @type {__VLS_StyleScopedClasses['md:grid-cols-2']} */ ;
        if (record.walletIsSender) {
            __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                ...{ class: "rounded-3xl border border-white/8 bg-white/[0.03] p-4 text-white/65" },
            });
            /** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
            /** @type {__VLS_StyleScopedClasses['border']} */ ;
            /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
            /** @type {__VLS_StyleScopedClasses['bg-white/[0.03]']} */ ;
            /** @type {__VLS_StyleScopedClasses['p-4']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-white/65']} */ ;
            __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
            });
            /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
            /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
            /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
            __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                ...{ class: "mt-2 text-lg font-semibold text-rose-200" },
            });
            /** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-lg']} */ ;
            /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-rose-200']} */ ;
            (__VLS_ctx.outgoingBalanceLabel(record));
            __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                ...{ class: "mt-1 text-xs text-white/45" },
            });
            /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
            (record.sourceChainLabel);
        }
        if (record.walletIsRecipient) {
            __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                ...{ class: "rounded-3xl border border-white/8 bg-white/[0.03] p-4 text-white/65" },
            });
            /** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
            /** @type {__VLS_StyleScopedClasses['border']} */ ;
            /** @type {__VLS_StyleScopedClasses['border-white/8']} */ ;
            /** @type {__VLS_StyleScopedClasses['bg-white/[0.03]']} */ ;
            /** @type {__VLS_StyleScopedClasses['p-4']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-white/65']} */ ;
            __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
            });
            /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
            /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
            /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
            __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                ...{ class: "mt-2 text-lg font-semibold text-emerald-200" },
            });
            /** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-lg']} */ ;
            /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-emerald-200']} */ ;
            (__VLS_ctx.incomingBalanceLabel(record));
            __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                ...{ class: "mt-1 text-xs text-white/45" },
            });
            /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-white/45']} */ ;
            (__VLS_ctx.incomingBalanceNote(record));
        }
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
            ...{ class: "mt-4 grid gap-3 text-sm text-white/50 md:grid-cols-2 xl:grid-cols-4" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-4']} */ ;
        /** @type {__VLS_StyleScopedClasses['grid']} */ ;
        /** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/50']} */ ;
        /** @type {__VLS_StyleScopedClasses['md:grid-cols-2']} */ ;
        /** @type {__VLS_StyleScopedClasses['xl:grid-cols-4']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
        });
        /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
        /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
        /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "mt-1 text-white" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white']} */ ;
        (record.detailLabel);
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
        });
        /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
        /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
        /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "mt-1 font-mono text-white/70" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
        /** @type {__VLS_StyleScopedClasses['font-mono']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/70']} */ ;
        (__VLS_ctx.shortenAddress(record.sender, 5));
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
        });
        /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
        /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
        /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "mt-1 font-mono text-white/70" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
        /** @type {__VLS_StyleScopedClasses['font-mono']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/70']} */ ;
        (__VLS_ctx.shortenAddress(record.recipient, 5));
        __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
        });
        /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
        /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
        /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
        __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
            ...{ class: "mt-1 font-mono text-white/70" },
        });
        /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
        /** @type {__VLS_StyleScopedClasses['font-mono']} */ ;
        /** @type {__VLS_StyleScopedClasses['text-white/70']} */ ;
        (__VLS_ctx.shortenAddress(record.depositTransactionHash, 6));
        if (record.claimTransactionHash || record.claimTimestamp) {
            __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                ...{ class: "mt-4 grid gap-3 text-sm text-white/50 md:grid-cols-2" },
            });
            /** @type {__VLS_StyleScopedClasses['mt-4']} */ ;
            /** @type {__VLS_StyleScopedClasses['grid']} */ ;
            /** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-white/50']} */ ;
            /** @type {__VLS_StyleScopedClasses['md:grid-cols-2']} */ ;
            if (record.claimTransactionHash) {
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
                });
                /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
                /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
                /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "mt-1 font-mono text-white/70" },
                });
                /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
                /** @type {__VLS_StyleScopedClasses['font-mono']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white/70']} */ ;
                (__VLS_ctx.shortenAddress(record.claimTransactionHash, 6));
            }
            if (record.claimTimestamp) {
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "text-[11px] uppercase tracking-[0.18em] text-white/35" },
                });
                /** @type {__VLS_StyleScopedClasses['text-[11px]']} */ ;
                /** @type {__VLS_StyleScopedClasses['uppercase']} */ ;
                /** @type {__VLS_StyleScopedClasses['tracking-[0.18em]']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white/35']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "mt-1 text-white" },
                });
                /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-white']} */ ;
                (__VLS_ctx.formatTimestamp(record.claimTimestamp));
            }
        }
        if (record.state === 'claimable') {
            __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                ...{ class: "xl:ml-4 xl:w-64" },
            });
            /** @type {__VLS_StyleScopedClasses['xl:ml-4']} */ ;
            /** @type {__VLS_StyleScopedClasses['xl:w-64']} */ ;
            __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                ...{ class: "rounded-3xl border border-cyan-300/20 bg-cyan-300/10 p-4" },
            });
            /** @type {__VLS_StyleScopedClasses['rounded-3xl']} */ ;
            /** @type {__VLS_StyleScopedClasses['border']} */ ;
            /** @type {__VLS_StyleScopedClasses['border-cyan-300/20']} */ ;
            /** @type {__VLS_StyleScopedClasses['bg-cyan-300/10']} */ ;
            /** @type {__VLS_StyleScopedClasses['p-4']} */ ;
            __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                ...{ class: "text-sm font-semibold text-cyan-50" },
            });
            /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
            /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-cyan-50']} */ ;
            __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                ...{ class: "mt-2 text-sm text-cyan-50/80" },
            });
            /** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-cyan-50/80']} */ ;
            (record.destinationChainLabel);
            if (__VLS_ctx.claimingTransferId === record.id) {
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                    ...{ class: "mt-4 rounded-2xl border border-cyan-200/20 bg-cyan-950/20 p-3 text-cyan-50/80" },
                });
                /** @type {__VLS_StyleScopedClasses['mt-4']} */ ;
                /** @type {__VLS_StyleScopedClasses['rounded-2xl']} */ ;
                /** @type {__VLS_StyleScopedClasses['border']} */ ;
                /** @type {__VLS_StyleScopedClasses['border-cyan-200/20']} */ ;
                /** @type {__VLS_StyleScopedClasses['bg-cyan-950/20']} */ ;
                /** @type {__VLS_StyleScopedClasses['p-3']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-cyan-50/80']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({
                    ...{ class: "flex items-start gap-3" },
                });
                /** @type {__VLS_StyleScopedClasses['flex']} */ ;
                /** @type {__VLS_StyleScopedClasses['items-start']} */ ;
                /** @type {__VLS_StyleScopedClasses['gap-3']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.div)({
                    ...{ class: "mt-1 h-4 w-4 animate-spin rounded-full border-2 border-cyan-100 border-t-transparent" },
                });
                /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
                /** @type {__VLS_StyleScopedClasses['h-4']} */ ;
                /** @type {__VLS_StyleScopedClasses['w-4']} */ ;
                /** @type {__VLS_StyleScopedClasses['animate-spin']} */ ;
                /** @type {__VLS_StyleScopedClasses['rounded-full']} */ ;
                /** @type {__VLS_StyleScopedClasses['border-2']} */ ;
                /** @type {__VLS_StyleScopedClasses['border-cyan-100']} */ ;
                /** @type {__VLS_StyleScopedClasses['border-t-transparent']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.div, __VLS_intrinsics.div)({});
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "text-sm font-semibold text-cyan-50" },
                });
                /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
                /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-cyan-50']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "mt-1 text-xs" },
                });
                /** @type {__VLS_StyleScopedClasses['mt-1']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
                __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                    ...{ class: "mt-2 text-xs" },
                });
                /** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
                /** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
                (__VLS_ctx.formatDuration(Math.max(__VLS_ctx.claimElapsedSeconds, 1)));
                if (__VLS_ctx.claimElapsedSeconds >= 20) {
                    __VLS_asFunctionalElement1(__VLS_intrinsics.p, __VLS_intrinsics.p)({
                        ...{ class: "mt-2 text-xs text-cyan-50/70" },
                    });
                    /** @type {__VLS_StyleScopedClasses['mt-2']} */ ;
                    /** @type {__VLS_StyleScopedClasses['text-xs']} */ ;
                    /** @type {__VLS_StyleScopedClasses['text-cyan-50/70']} */ ;
                }
            }
            __VLS_asFunctionalElement1(__VLS_intrinsics.button, __VLS_intrinsics.button)({
                ...{ onClick: (...[$event]) => {
                        if (!!(__VLS_ctx.loading && __VLS_ctx.transferRecords.length === 0))
                            return;
                        if (!!(__VLS_ctx.errorMessage))
                            return;
                        if (!!(__VLS_ctx.transferRecords.length === 0))
                            return;
                        if (!!(__VLS_ctx.visibleTransfers.length === 0))
                            return;
                        if (!(record.state === 'claimable'))
                            return;
                        __VLS_ctx.receiveTransfer(record);
                        // @ts-ignore
                        [formatDuration, formatDuration, formatTimestamp, formatTimestamp, transferRecords, errorMessage, errorMessage, swapStore, swapStore, visibleTransfers, visibleTransfers, stateBadgeClass, formatUnits, progressWidth, outgoingBalanceLabel, incomingBalanceLabel, incomingBalanceNote, shortenAddress, shortenAddress, shortenAddress, shortenAddress, claimingTransferId, claimElapsedSeconds, claimElapsedSeconds, receiveTransfer,];
                    } },
                type: "button",
                ...{ class: "mt-4 w-full rounded-2xl bg-cyan-300 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50" },
                disabled: (__VLS_ctx.claimingTransferId !== null),
            });
            /** @type {__VLS_StyleScopedClasses['mt-4']} */ ;
            /** @type {__VLS_StyleScopedClasses['w-full']} */ ;
            /** @type {__VLS_StyleScopedClasses['rounded-2xl']} */ ;
            /** @type {__VLS_StyleScopedClasses['bg-cyan-300']} */ ;
            /** @type {__VLS_StyleScopedClasses['px-4']} */ ;
            /** @type {__VLS_StyleScopedClasses['py-3']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-sm']} */ ;
            /** @type {__VLS_StyleScopedClasses['font-semibold']} */ ;
            /** @type {__VLS_StyleScopedClasses['text-slate-950']} */ ;
            /** @type {__VLS_StyleScopedClasses['transition']} */ ;
            /** @type {__VLS_StyleScopedClasses['hover:brightness-110']} */ ;
            /** @type {__VLS_StyleScopedClasses['disabled:cursor-not-allowed']} */ ;
            /** @type {__VLS_StyleScopedClasses['disabled:opacity-50']} */ ;
            (__VLS_ctx.claimButtonLabel(record));
        }
        // @ts-ignore
        [claimingTransferId, claimButtonLabel,];
    }
}
// @ts-ignore
[];
const __VLS_export = (await import('vue')).defineComponent({});
export default {};
