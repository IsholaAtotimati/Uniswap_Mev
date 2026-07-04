"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const assert_1 = __importDefault(require("assert"));
const PayloadSigner_1 = require("../src/engine/PayloadSigner");
const signer = new PayloadSigner_1.PayloadSigner();
assert_1.default.strictEqual(signer.sign(), 'payload signed');
console.log('PayloadSigner test passed');
