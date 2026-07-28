import { useState, useEffect, useRef } from "react";

export const SwapState = {
  IDLE: "IDLE",
  CONNECTING: "CONNECTING",
  ANALYZING: "ANALYZING",
  READY: "READY",
  SIGNING: "SIGNING",
  EXECUTING: "EXECUTING",
  SETTLING: "SETTLING",
  SUCCESS: "SUCCESS",
  ERROR: "ERROR",
};

export default function useProtectedSwap() {
  const [state, setState] = useState(SwapState.IDLE);
  const [risk, setRisk] = useState(null);
  const [signature, setSignature] = useState(null);
  const [txHash, setTxHash] = useState(null);
  const [payload, setPayload] = useState(null);
  const [settlementId, setSettlementId] = useState(null);
  const [settlementStatus, setSettlementStatus] = useState(null);
  const [error, setError] = useState(null);
  const pollingRef = useRef(null);

  useEffect(() => {
    // start polling when a settlementId is available
    if (!settlementId) return;

    const apiBase = import.meta.env.VITE_API_URL || "";
    const poll = async () => {
      try {
        const res = await fetch(`${apiBase}/settlement/status/${settlementId}`);
        if (!res.ok) throw new Error(`status ${res.status}`);
        const body = await res.json();
        const currentStatus = body.status || body.settlementStatus || body.state || null;
        setSettlementStatus(currentStatus);

        // map to local swap state when terminal
        const statusUpper = (currentStatus || "").toString().toUpperCase();
        const isSuccessful = ["COMPLETED", "EXECUTED"].includes(statusUpper);
        const isFailed = ["FAILED", "CANCELLED"].includes(statusUpper);
        
        if (isSuccessful || isFailed) {
          setState(isSuccessful ? SwapState.SUCCESS : SwapState.ERROR);
          if (pollingRef.current) {
            clearInterval(pollingRef.current);
            pollingRef.current = null;
          }
        } else {
          setState(SwapState.SETTLING);
        }
      } catch (err) {
        setError(err.message);
      }
    };

    // do an immediate fetch then interval
    poll();
    pollingRef.current = setInterval(poll, 3000);

    return () => {
      if (pollingRef.current) clearInterval(pollingRef.current);
      pollingRef.current = null;
    };
  }, [settlementId]);

  return {
    state,
    setState,
    risk,
    setRisk,
    signature,
    setSignature,
    txHash,
    setTxHash,
    payload,
    setPayload,
    settlementId,
    setSettlementId,
    settlementStatus,
    setSettlementStatus,
    error,
    setError,
  };
}