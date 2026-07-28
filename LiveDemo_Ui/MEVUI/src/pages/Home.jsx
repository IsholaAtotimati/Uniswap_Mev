import Header from "../components/Header";
import ExecutionStatus from "../components/ExecutionStatus";
import SwapCard from "../components/SwapCard";   // <-- ADD THIS
import useProtectedSwap from "../hooks/useProtectedSwap";

function Home() {

    const swap = useProtectedSwap();

    return (
        <>
             <SwapCard swap={swap} />
            <ExecutionStatus state={swap.state} />

        </>
    );

}

export default Home;