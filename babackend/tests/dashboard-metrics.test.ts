import { AddressInfo } from "node:net";
import { app } from "../src/app.js";

describe("dashboard metrics API", () => {
  let server: ReturnType<typeof app.listen>;

  beforeAll(async () => {
    server = await new Promise<ReturnType<typeof app.listen>>((resolve) => {
      const instance = app.listen(0, () => resolve(instance));
    });
  });

  afterAll(async () => {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  });

  it("serves dashboard metrics for the frontend", async () => {
    const address = server.address() as AddressInfo;
    const response = await fetch(`http://127.0.0.1:${address.port}/api/dashboard/metrics`);
    expect(response.status).toBe(200);

    const payload = await response.json();
    expect(payload.success).toBe(true);
    expect(payload.data).toBeDefined();
    expect(payload.data.totalValue).toBeDefined();
  });
});
