"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const assert_1 = __importDefault(require("assert"));
const SandwichDetector_1 = require("../src/detectors/SandwichDetector");
const detector = new SandwichDetector_1.SandwichDetector();
assert_1.default.strictEqual(detector.detect(), 'sandwich detector ready');
console.log('SandwichDetector test passed');
