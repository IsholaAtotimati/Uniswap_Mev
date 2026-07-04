"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const assert_1 = __importDefault(require("assert"));
const FeeRecommendationEngine_1 = require("../src/engine/FeeRecommendationEngine");
const engine = new FeeRecommendationEngine_1.FeeRecommendationEngine();
assert_1.default.strictEqual(engine.recommend(), 'fee recommended');
console.log('FeeEngine test passed');
