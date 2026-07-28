import axios from "axios";


const API_URL = "http://localhost:3000";


export async function analyzeRisk(payload){

    const response = await axios.post(
        `${API_URL}/api/analyze`,
        payload
    );


    return response.data;

}