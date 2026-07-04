import { ethers } from "ethers";
import { DOMAIN, TYPES } from "../config/typedData.js";
export class SignatureService {
    privateKey;
    wallet;
    constructor(privateKey) {
        this.privateKey = privateKey;
        this.wallet = new ethers.Wallet(privateKey);
    }
    async sign(payload) {
        const signature = await this.wallet.signTypedData(DOMAIN, TYPES, payload);
        return signature;
    }
    verify(payload, signature) {
        return ethers.verifyTypedData(DOMAIN, TYPES, payload, signature);
    }
}
