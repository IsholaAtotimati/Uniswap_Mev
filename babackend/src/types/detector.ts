export interface DetectorResult {
  detected: boolean;
  severity: 'low' | 'medium' | 'high';
  reason: string;
}
