/** Invalidează răspunsurile vechi inclusiv dacă transportul ignoră anularea. */
export class LatestRequest {
  private version = 0;
  private controller: AbortController | null = null;

  invalidate(): void {
    this.version += 1;
    this.controller?.abort();
    this.controller = null;
  }

  start() {
    this.invalidate();
    const version = this.version;
    const controller = new AbortController();
    this.controller = controller;
    return { signal: controller.signal, isCurrent: () => version === this.version && !controller.signal.aborted };
  }
}
