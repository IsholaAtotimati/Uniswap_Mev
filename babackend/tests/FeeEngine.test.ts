import assert from 'assert';
import { FeeRecommendationEngine } from '../src/engine/FeeRecommendationEngine';

const engine = new FeeRecommendationEngine();
assert.strictEqual(engine.recommend(), 'fee recommended');
console.log('FeeEngine test passed');
