import { useEffect, useState } from "react";
import {
    analyzeRisk as analyzeRiskAPI,
    createExecutionIntent
} from "../services/executionIntent";
import RiskPanel from "./RiskPanel";
import api from "../services/api";

function SwapCard({ swap }) {

    const [amount, setAmount] = useState("1");
    const [loading, setLoading] = useState(false);
    const [result, setResult] = useState(null);
    const [statusError, setStatusError] = useState(null);

    useEffect(() => {
        let interval;

        if (swap.settlementId && swap.state !== "SUCCESS" && swap.state !== "ERROR") {
            interval = window.setInterval(() => {
                fetchSettlementStatus();
            }, 5000);
        }

        return () => {
            if (interval) {
                window.clearInterval(interval);
            }
        };
    }, [swap.settlementId, swap.state]);

    async function fetchSettlementStatus() {
        if (!swap.settlementId) {
            return;
        }

        try {
            const res = await api.get(`/settlement/status/${swap.settlementId}`);
            const status = res.data.status;

            swap.setSettlementStatus(status);
            setStatusError(null);

            if (status === "completed") {
                swap.setState("SUCCESS");
            } else if (status === "failed" || status === "cancelled") {
                swap.setState("ERROR");
            } else if (status === "submitted" || status === "pending") {
                if (swap.state !== "SETTLING") {
                    swap.setState("SETTLING");
                }
            }
        } catch (err) {
            console.error("Polling settlement status failed", err);
            setStatusError("Unable to refresh settlement status");
        }
    }

    async function analyzeRisk() {

        if (!amount || Number(amount) <= 0) {
            alert("Enter swap amount");
            return;
        }

        try {

            swap.setState("ANALYZING");

            setLoading(true);

            const response = await analyzeRiskAPI({

                tokenIn: "ETH",
                tokenOut: "USDC",
                amount

            });

            setResult(response);

            swap.setRisk(response);

            swap.setState("READY");

        } catch (err) {

            console.error(err);

            swap.setState("ERROR");

        } finally {

            setLoading(false);

        }

    }
    async function executeProtectedSwap() {
        try {
            swap.setState("SIGNING");

            const intent = await createExecutionIntent({
                tokenIn: "ETH",
                tokenOut: "USDC",
                amount,
            });

            console.log("Execution intent:", intent);

            // store returned payload/signature/settlement id
            if (intent.signature) swap.setSignature(intent.signature);
            if (intent.payload) swap.setPayload(intent.payload);
            if (intent.settlementId) swap.setSettlementId(intent.settlementId);
            if (intent.txHash) swap.setTxHash(intent.txHash);
            if (intent.settlementStatus) swap.setSettlementStatus(intent.settlementStatus);

            if (intent.status === "submitted") {
                swap.setState("SETTLING");
            } else if (intent.status === "signed") {
                swap.setState("EXECUTING");
            } else {
                swap.setState("SETTLING");
            }
        } catch (error) {
            console.error("Execution failed:", error);
            swap.setState("ERROR");
        }
    }

    return (

        <div className="swap-card">

            <h2>Protected Swap</h2>

            <label>From</label>

            <div>

                <select>
                    <option>ETH</option>
                </select>

                <input
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                    placeholder="0.0"
                />

            </div>

            <label>To</label>

            <div>

                <select>
                    <option>USDC</option>
                </select>

            </div>

            <button onClick={analyzeRisk}>

                {loading ? "Analyzing..." : "Analyze Risk"}

            </button>

            <RiskPanel result={result} />

            {result && (
                <div className="protection-summary">
                    <h3>Protection Summary</h3>
                    <div>Recommended Spread: {result.recommendedSpread}</div>
                    <div>Fee: {result.feePercent}</div>
                    <div>Expected LP Loss (USD): {result.expectedLpLossUSD}</div>
                    <div>Expected Price Impact: {result.expectedPriceImpact}</div>
                </div>
            )}

            {swap.payload && (
                <div className="signed-policy">
                    <h3>Signed Policy</h3>
                    <div>Nonce: {swap.payload.nonce}</div>
                    <div>Expiry: {swap.payload.expiry ? new Date(swap.payload.expiry * 1000).toLocaleString() : "-"}</div>
                    <div>Signer: {swap.payload.signer}</div>
                    <div>Settlement Token: {swap.payload.settlementToken || "USDC"}</div>
                    <div>Settlement Amount: {swap.payload.settlementAmount}</div>
                    <div>Signature: {swap.signature}</div>
                </div>
            )}

            <div className="workflow">
                <h3>Workflow</h3>
                <ol>
                    <li style={{ fontWeight: swap.state === "ANALYZING" ? "bold" : "normal" }}>Analyze Risk</li>
                    <li style={{ fontWeight: swap.state === "READY" ? "bold" : "normal" }}>Generate Policy</li>
                    <li style={{ fontWeight: swap.state === "SIGNING" ? "bold" : "normal" }}>User Signs</li>
                    <li style={{ fontWeight: swap.state === "EXECUTING" ? "bold" : "normal" }}>Submit to Hook</li>
                    <li style={{ fontWeight: swap.state === "SETTLING" ? "bold" : "normal" }}>Settle</li>
                    <li style={{ fontWeight: swap.state === "SUCCESS" ? "bold" : "normal" }}>Completed</li>
                </ol>
            </div>

            {swap.state === "READY" && (
                <button onClick={executeProtectedSwap}>
                    Programmable Execution Security Layer for USDC
                </button>
            )}

            {swap.settlementId && (
                <div className="settlement">
                    <h3>Settlement</h3>
                    <div>ID: {swap.settlementId}</div>
                    <div>Status: {swap.settlementStatus || "pending"}</div>
                    {swap.lastError && <div className="error-text">Reason: {swap.lastError}</div>}
                    {statusError && <div className="error-text">{statusError}</div>}
                    <button onClick={fetchSettlementStatus}>
                        Refresh Status
                    </button>
                </div>
            )}

        </div>

    );

}

export default SwapCard;