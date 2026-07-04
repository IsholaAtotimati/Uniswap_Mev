import { ethers } from "ethers";
import { SignatureService } from "../services/SignatureService.js";
import { PayloadBuilder } from "../engine/PayloadBuilder.js";
import { RiskLevel } from "../types/enums.js";
async function main() {
    const privateKey = process.env.PRIVATE_KEY || "";
    const verifyingContract = process.env.VERIFYING_CONTRACT || "";
    const chainId = process.env.CHAIN_ID ? Number(process.env.CHAIN_ID) : undefined;
    if (!privateKey) {
        throw new Error("PRIVATE_KEY is required to generate a signed payload.");
    }
    if (!verifyingContract) {
        throw new Error("VERIFYING_CONTRACT is required to generate a signed payload.");
    }
    if (chainId === undefined) {
        throw new Error("CHAIN_ID is required to generate a signed payload.");
    }
    const signer = new ethers.Wallet(privateKey).address;
    const payloadBuilder = new PayloadBuilder();
    const signatureService = new SignatureService(privateKey);
    const sampleResult = {
        sandwichScore: 0.42,
        toxicityScore: 75,
        arbitrageScore: 0.18,
        walletScore: 0.55,
        volatilityScore: 0.22,
        finalRiskScore: 7400,
        confidence: 0.92,
        riskLevel: RiskLevel.HIGH,
        expectedLpLossUSD: 128000,
        expectedLeakageUSD: 52000,
        expectedPriceImpact: 0.014,
        recommendedSpread: 1200
    };
    const poolKey = {
        currency0: "0x0000000000000000000000000000000000001000",
        currency1: "0x0000000000000000000000000000000000002000",
        fee: 3000,
        tickSpacing: 60,
        hooks: "0x0000000000000000000000000000000000000000"
    };
    const abiCoder = new ethers.AbiCoder();
    const poolId = ethers.keccak256(abiCoder.encode(["address", "address", "uint24", "int24", "address"], [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]));
    const payloadPoolId = ethers.keccak256(poolId);
    const payload = payloadBuilder.build(sampleResult, payloadPoolId, signer, 600);
    const signature = await signatureService.sign(payload);
    console.log(JSON.stringify({ payload, signature }));
}
main().catch((error) => {
    console.error(error);
    process.exit(1);
});
