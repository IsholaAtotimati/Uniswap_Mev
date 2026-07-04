import assert from 'assert';
import { RiskEngine } from '../src/engine/RiskEngine';

const engine = new RiskEngine();
assert.strictEqual(engine.evaluate(), 'risk engine initialized');
console.log('RiskEngine test passed');
