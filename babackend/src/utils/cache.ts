export class SimpleCache<T> {
  private store = new Map<string, T>();

  public set(key: string, value: T): void {
    this.store.set(key, value);
  }

  public get(key: string): T | undefined {
    return this.store.get(key);
  }
}
