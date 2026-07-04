import { ethers } from "ethers";
import { DOMAIN, TYPES } from "../config/typedData.js";
import { SignedRiskPayload } from "../types/signedPayload.js";

export class SignatureService {

    private wallet: ethers.Wallet;

    constructor(private privateKey: string){
        this.wallet = new ethers.Wallet(privateKey);
    }

    async sign(payload: SignedRiskPayload): Promise<string> {

        const signature = await this.wallet.signTypedData(
            DOMAIN,
            TYPES,
            payload
        );

        return signature;
    }

    verify(
        payload: SignedRiskPayload,
        signature: string
    ): string {

        return ethers.verifyTypedData(
            DOMAIN,
            TYPES,
            payload,
            signature
        );
    }
}