"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const assert_1 = __importDefault(require("assert"));
const RiskEngine_1 = require("../src/engine/RiskEngine");
const engine = new RiskEngine_1.RiskEngine();
assert_1.default.strictEqual(engine.evaluate(), 'risk engine initialized');
console.log('RiskEngine test passed');
