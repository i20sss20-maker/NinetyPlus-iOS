# 90+ free gateway

The app works directly with public sources without deploying this optional gateway.
The gateway uses Cloudflare Workers' Free plan, with no paid sports API key.
It proxies only the supported ESPN football and TheSportsDB player routes and caches
successful responses. Neither hosting nor public-source availability is unlimited.
Coverage is limited to the supported leagues and provider-published records.

## Deploy in your own Cloudflare account

1. Select the Workers Free plan in your account; no paid upgrade is required.
2. From this directory, run `npx wrangler login`, then `npx wrangler deploy`.
3. Open the returned HTTPS `workers.dev` address with `/api/health` appended.
4. In 90+, open **المزيد → مصادر البيانات**, paste the base URL, and save it.
5. Open Matches and Search and confirm actual data appears. A health response alone
   proves only the gateway is reachable. On gateway failure, the app retries the
   public source directly; fixture snapshots remain on the device with stale labels.

No deployment has been performed merely by adding these files. No credentials
should be added to the repository. `node --test worker.test.mjs` tests routing.
