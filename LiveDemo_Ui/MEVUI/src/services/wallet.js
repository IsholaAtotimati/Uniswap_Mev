import {
    createWalletClient,
    custom,
    getAddress
} from "viem";


let walletClient = null;
let walletAddress = null;


export async function connectWallet(){

    if(!window.ethereum){
        throw new Error("No wallet detected");
    }

    walletClient = createWalletClient({
        transport: custom(window.ethereum)
    });


    const accounts =
        await walletClient.requestAddresses();


    walletAddress = getAddress(accounts[0]);

    return walletAddress;
}


export function getWalletAddress(){

    return walletAddress;

}


export function disconnectWallet(){

    walletClient = null;
    walletAddress = null;

}


export function getWalletClient(){

    return walletClient;

}
