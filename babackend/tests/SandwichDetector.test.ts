import assert from 'assert';
import { SandwichDetector } from '../src/detectors/SandwichDetector';

const detector = new SandwichDetector();
assert.strictEqual(detector.detect(), 'sandwich detector ready');
console.log('SandwichDetector test passed');
