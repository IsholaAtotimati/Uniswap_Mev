function RiskPanel({ result }) {

    if (!result) return null;

    const riskLevelColor = result.riskLevel === "CRITICAL" ? "red" : 
                          result.riskLevel === "HIGH" ? "orange" : 
                          result.riskLevel === "MEDIUM" ? "yellow" : "green";

    return (

        <div className="risk-panel" style={{ borderLeft: `4px solid ${riskLevelColor}` }}>

            <h3>Risk Analysis</h3>

            <p>Risk Score: <strong>{result.riskScore ?? "N/A"}</strong></p>

            <p>Risk Level: <strong style={{ color: riskLevelColor }}>{result.riskLevel ?? "UNKNOWN"}</strong></p>

            <p>Toxicity: <strong>{result.toxicity ?? "UNKNOWN"}</strong></p>

            <p>Expected Loss: <strong>${(result.expectedLpLossUSD ?? 0).toFixed(2)}</strong></p>

            <p>MEV Leakage: <strong>${(result.expectedLeakageUSD ?? 0).toFixed(2)}</strong></p>

            <p>Protection Fee: <strong>{result.feePercent ?? "0%"}</strong></p>

            <p>Confidence: <strong>{((result.confidence ?? 0) * 100).toFixed(0)}%</strong></p>

        </div>

    );

}

export default RiskPanel;