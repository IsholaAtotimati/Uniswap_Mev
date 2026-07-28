import "./ExecutionStatus.css";

function ExecutionStatus({ state }) {

    return (

        <div className="execution">

            <h2>Execution Status</h2>

            <p>{state}</p>

        </div>

    );

}

export default ExecutionStatus;