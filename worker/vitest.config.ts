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
