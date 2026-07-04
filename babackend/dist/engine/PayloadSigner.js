import { SignatureService } from "../services/SignatureService.js";
export class PayloadSigner {
    privateKey;
    signatureService;
    constructor(privateKey) {
        this.privateKey = privateKey;
        this.signatureService = new SignatureService(privateKey);
    }
    async sign(payload) {
        return this.signatureService.sign(payload);
    }
}
