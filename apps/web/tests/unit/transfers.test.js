import { describe, expect, it } from "vitest";
import { applyTransferRuntimeState, buildTransferRecords, markTransferRecordReceived, } from "@/services/transfers";
describe("transfer history model", () => {
    it("marks a transfer complete when a matching claim exists", () => {
        const deposits = [
            {
                id: "deposit-1",
                user_id: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                token_id: "0x0000000000000000000000000000000000000000",
                to: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                amount: "1000000000000000000",
                sourceChain: "1",
                destinationChain: "8453",
                blockNumber: "25",
                depositIndex: "0",
                depositRoot: "0xabc",
                transactionHash: "0xdeposit",
                timestamp: "100",
            },
        ];
        const claims = [
            {
                id: "claim-1",
                user_id: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                token_id: "0x0000000000000000000000000000000000000000",
                to: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                amount: "1000000000000000000",
                sourceChain: "1",
                destinationChain: "8453",
                transactionHash: "0xclaim",
                timestamp: "109",
                deposit_id: "1-0",
            },
        ];
        const attestations = [
            {
                id: "attestation-1",
                validator: "0xvalidator-1",
                sourceChainId: "1",
                sourceBlockNumber: "0",
                bridgeRoot: "0xabc",
                blockTimestamp: "105",
            },
        ];
        const [record] = buildTransferRecords("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", deposits, claims, attestations, 110);
        expect(record.state).toBe("complete");
        expect(record.claimTransactionHash).toBe("0xclaim");
        expect(record.durationSeconds).toBe(9);
        expect(record.assetDecimals).toBe(18);
    });
    it("marks a transfer as attesting when validator activity exists without a claim", () => {
        const deposits = [
            {
                id: "deposit-2",
                user_id: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                token_id: "0x0000000000000000000000000000000000000000",
                to: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                amount: "1000000000000000000",
                sourceChain: "1",
                destinationChain: "8453",
                blockNumber: "25",
                depositIndex: "25",
                depositRoot: "0xdef",
                transactionHash: "0xdeposit-2",
                timestamp: "200",
            },
        ];
        const claims = [];
        const attestations = [
            {
                id: "attestation-2",
                validator: "0xvalidator-1",
                sourceChainId: "1",
                sourceBlockNumber: "25",
                bridgeRoot: "0xdef",
                blockTimestamp: "203",
            },
            {
                id: "attestation-3",
                validator: "0xvalidator-2",
                sourceChainId: "1",
                sourceBlockNumber: "25",
                bridgeRoot: "0xdef",
                blockTimestamp: "204",
            },
        ];
        const [record] = buildTransferRecords("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", deposits, claims, attestations, 205);
        expect(record.state).toBe("attesting");
        expect(record.attestationCount).toBe(2);
        expect(record.durationSeconds).toBe(5);
    });
    it("matches attestations using the source block number rather than the deposit index", () => {
        const deposits = [
            {
                id: "deposit-3",
                user_id: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                token_id: "0x0000000000000000000000000000000000000000",
                to: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                amount: "500000000000000000",
                sourceChain: "1",
                destinationChain: "8453",
                blockNumber: "88",
                depositIndex: "7",
                depositRoot: "0xfeed",
                transactionHash: "0xdeposit-3",
                timestamp: "300",
            },
        ];
        const claims = [];
        const attestations = [
            {
                id: "attestation-4",
                validator: "0xvalidator-1",
                sourceChainId: "1",
                sourceBlockNumber: "88",
                bridgeRoot: "0xfeed",
                blockTimestamp: "305",
            },
            {
                id: "attestation-5",
                validator: "0xvalidator-1",
                sourceChainId: "1",
                sourceBlockNumber: "88",
                bridgeRoot: "0xfeed",
                blockTimestamp: "306",
            },
        ];
        const [record] = buildTransferRecords("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", deposits, claims, attestations, 310);
        expect(record.state).toBe("attesting");
        expect(record.attestationCount).toBe(1);
    });
    it("marks a transfer ready to receive when the destination root is verified", () => {
        const deposits = [
            {
                id: "deposit-4",
                user_id: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                token_id: "0x0000000000000000000000000000000000000000",
                to: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                amount: "1000000000000000000",
                sourceChain: "1",
                destinationChain: "8453",
                blockNumber: "91",
                depositIndex: "8",
                depositRoot: "0xbeef",
                transactionHash: "0xdeposit-4",
                timestamp: "400",
            },
        ];
        const claims = [];
        const attestations = [
            {
                id: "attestation-6",
                validator: "0xvalidator-1",
                sourceChainId: "1",
                sourceBlockNumber: "91",
                bridgeRoot: "0xbeef",
                blockTimestamp: "405",
            },
        ];
        const [record] = buildTransferRecords("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", deposits, claims, attestations, 410);
        const runtimeState = new Map([
            [
                "8453:1:91:0xbeef",
                {
                    claimable: true,
                    sourceStateRoot: "0x00000000000000000000000000000000000000000000000000000000000000ff",
                },
            ],
        ]);
        const [hydratedRecord] = applyTransferRuntimeState([record], runtimeState);
        expect(hydratedRecord.state).toBe("claimable");
        expect(hydratedRecord.stateLabel).toBe("Ready to receive");
        expect(hydratedRecord.sourceStateRoot).toBe("0x00000000000000000000000000000000000000000000000000000000000000ff");
    });
    it("marks a transfer received immediately after a successful claim", () => {
        const deposits = [
            {
                id: "deposit-5",
                user_id: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                token_id: "0x0000000000000000000000000000000000000000",
                to: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
                amount: "2500000000000000000",
                sourceChain: "31338",
                destinationChain: "31339",
                blockNumber: "120",
                depositIndex: "3",
                depositRoot: "0xcafe",
                transactionHash: "0xdeposit-5",
                timestamp: "500",
            },
        ];
        const [record] = buildTransferRecords("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", deposits, [], [], 530);
        const receivedRecord = markTransferRecordReceived(record, 540, "0xclaim-local");
        expect(receivedRecord.state).toBe("complete");
        expect(receivedRecord.stateLabel).toBe("Received");
        expect(receivedRecord.claimTransactionHash).toBe("0xclaim-local");
        expect(receivedRecord.claimTimestamp).toBe(540);
        expect(receivedRecord.durationSeconds).toBe(40);
    });
});
