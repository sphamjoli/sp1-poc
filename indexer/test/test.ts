import { strict as assert } from "node:assert";
import {
  resolveAttestationTimestamp,
  resolveSourceBlockNumber,
  resolveSourceChainId,
  resolveClaimClaimer,
  resolveClaimRecipient,
  resolveEventSourceAddress,
  resolveStateRoot,
} from "../src/params";

describe("event param resolvers", () => {
  it("resolves Claimed event aliases", () => {
    assert.equal(resolveClaimClaimer({ claimer: "0xabc" }), "0xabc");
    assert.equal(resolveClaimClaimer({ who: "0xdef" }), "0xdef");

    assert.equal(resolveClaimRecipient({ recipient: "0x111" }, "0xfallback"), "0x111");
    assert.equal(resolveClaimRecipient({ to: "0x222" }, "0xfallback"), "0x222");
    assert.equal(resolveClaimRecipient({}, "0xfallback"), "0xfallback");
  });

  it("resolves AttestationSubmitted fields and defaults", () => {
    assert.equal(resolveSourceChainId({ sourceChainId: 8453 }).toString(), "8453");

    assert.equal(resolveSourceBlockNumber({ blockNumber: 300 }).toString(), "300");
    assert.equal(resolveSourceBlockNumber({ sourceBlockNumber: 55 }).toString(), "55");

    assert.equal(
      resolveStateRoot({}),
      "0x0000000000000000000000000000000000000000000000000000000000000000",
    );

    assert.equal(resolveAttestationTimestamp({}, 123n).toString(), "123");
    assert.equal(resolveAttestationTimestamp({ timestamp: 999 }, 123n).toString(), "999");
  });

  it("resolves Envio source address field for validator manager events", () => {
    assert.equal(
      resolveEventSourceAddress({ srcAddress: "0xfeedface" }, "0xfallback"),
      "0xfeedface",
    );
    assert.equal(resolveEventSourceAddress({}, "0xfallback"), "0xfallback");
  });
});
