import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config';

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        // Single worker + non-isolated storage: each test resets the D1
        // schema explicitly via resetDb() (test/helpers.ts). This keeps
        // test isolation deterministic and independent of pool-level
        // storage semantics.
        singleWorker: true,
        isolatedStorage: false,
        wrangler: { configPath: './wrangler.toml' },
        // wrangler.toml declares an [ai] binding. vitest-pool-workers ≥0.12
        // opens a REMOTE proxy session for AI/Vectorize bindings by default,
        // which requires wrangler authentication — unavailable (and unwanted)
        // in CI. No production code path under test calls env.AI from the
        // suite's real runtime binding: ai.test.ts injects a hermetic mock
        // AI binding directly into handleAiRequest, so remote access is
        // never needed. Keep tests hermetic and credential-free.
        remoteBindings: false,
        miniflare: {
          // JWT_SECRET is a Cloudflare Secret in production (never in
          // wrangler.toml) — injected here for tests only.
          bindings: {
            JWT_SECRET: 'test-only-secret-0123456789abcdef',
          },
        },
      },
    },
  },
});
