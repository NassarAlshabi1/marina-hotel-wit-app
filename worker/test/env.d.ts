// Augment the cloudflare:test ProvidedEnv with the worker's real Env
// (D1 + Durable Object namespace + vars + the test JWT_SECRET binding
// injected via vitest.config.ts miniflare bindings).
import type { Env } from '../src/index';

declare module 'cloudflare:test' {
  // eslint-disable-next-line @typescript-eslint/no-empty-interface
  interface ProvidedEnv extends Env {}
}
