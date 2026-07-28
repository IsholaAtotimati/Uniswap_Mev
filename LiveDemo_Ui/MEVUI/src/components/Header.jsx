import { useState } from "react";
import {
    connectWallet,
    getWalletAddress
} from "../services/wallet";


export default function Header(){

    const [address,setAddress] = useState(null);


    async function handleConnect(){

        try{

            const wallet =
                await connectWallet();

            setAddress(wallet);

        }
        catch(error){

            console.log(error.message);

        }

    }


    return (

        <header className="header">

            <h1>
                MEV Shield
            </h1>
            <h3>Powered by 
                ARC,
                USDC.
                Circle Wallets
                & circle app kit
                
            </h3>

            <button
              onClick={handleConnect}
            >

            {
                address
                ?
                `${address.slice(0,6)}...${address.slice(-4)}`
                :
                "Connect Wallet"
            }

            </button>


        </header>

    );

}