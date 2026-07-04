import assert from 'assert';
import { PayloadSigner } from '../src/engine/PayloadSigner';

const signer = new PayloadSigner();
assert.strictEqual(signer.sign(), 'payload signed');
console.log('PayloadSigner test passed');
