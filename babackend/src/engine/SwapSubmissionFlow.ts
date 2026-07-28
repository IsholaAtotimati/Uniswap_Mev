import { ethers } from "ethers";

export function normalizeSettlementAmount(value: number | string | bigint | null | undefined): number {
    if (value === null || value === undefined) {
        return 1;
    }

    if (typeof value === "bigint") {
        return value > 0n ? Number(value) : 1;
    }

    if (typeof value === "number") {
        if (!Number.isFinite(value)) {
            return 1;
        }
        const rounded = Math.round(value);
        return rounded > 0 ? rounded : 1;
    }

    if (typeof value === "string") {
        const trimmed = value.trim();
        if (trimmed === "") {
            return 1;
        }

        const parsed = Number(trimmed);
        if (!Number.isFinite(parsed)) {
            return 1;
        }

        const rounded = Math.round(parsed);
        return rounded > 0 ? rounded : 1;
    }

    return 1;
}

export function buildSettlementId(poolId: string, nonce: number | bigint): string {
    return ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
            ["bytes32", "uint256"],
            [poolId, BigInt(nonce)]
        )
    );
}

export function toRecipientBytes32(recipient: string): string {
    if (!recipient || !ethers.isAddress(recipient)) {
        return ethers.toBeHex(ethers.ZeroAddress, 32);
    }

    return ethers.toBeHex(recipient, 32);
}
