export interface DetectorResult {

    name: string;

    score: number;

    confidence: number;

    reason: string;

    metadata?: Record<string, unknown>;

}