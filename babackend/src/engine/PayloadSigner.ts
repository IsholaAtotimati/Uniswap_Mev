import { SignatureService } from "../services/SignatureService.js";
import { SignedRiskPayload } from "../types/signedPayload.js";

export class PayloadSigner{
  private signatureService: SignatureService;

  constructor(private privateKey: string) {
    this.signatureService = new SignatureService(privateKey);
  }

  async sign(payload: SignedRiskPayload): Promise<string>{
    return this.signatureService.sign(payload);
  }
}
