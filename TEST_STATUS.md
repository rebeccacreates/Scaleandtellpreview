# Local validation report

Date: October 17, 2026. This is a **source/build check, not a Supabase integration test or real push receipt test**.

- `node --check` on extracted app inline JS and `sw.js`: syntax validated.
- `node --experimental-strip-types --check` on Edge TypeScript source: parses locally, but Deno/npm imports and Web Push runtime cannot be verified without staging.
- In-memory headless-browser smoke script: app initializes without a live Supabase SDK; confirms 5 PM default, optional pack price, original embedded artwork count, manual screenshot text, empty/populated printables, and that a failed server opt-out does not unsubscribe locally. Confirms category changes register only selected categories.
- Package/manifest/icon/static page existence checked. ZIP integrity check on final archive.
- The automated browser's network navigation was blocked by administrator policy in this workspace. In-memory HTML execution was used, **not** a live `localhost`/HTTPS origin. Worker registration, hosted redirect/auth, external Supabase endpoints and actual push cannot be claimed as tested here.
- SQL migration has not been executed against real PostgreSQL. It requires review/test in a properly isolated staging project.
