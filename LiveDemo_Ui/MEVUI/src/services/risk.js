import axios from "axios";

const API_URL = (import.meta.env.VITE_API_URL || "http://localhost:4000").replace(/\/$/, "");

export async function analyzeRisk(payload){

    const response = await axios.post(
        `${API_URL}/api/analyze`,
        payload
    );


    return response.data;

}