# SplitMate Supabase backend

## Apply migrations

From this directory (with [Supabase CLI](https://supabase.com/docs/guides/cli) installed and linked to your project):

```bash
supabase db push
```

Or paste [`migrations/20260422100000_splitmate_full_schema.sql`](migrations/20260422100000_splitmate_full_schema.sql) into the Supabase SQL Editor and run it **once on an empty project** (new database).

Older incremental migration files were removed in favor of this single file. If you still have an existing Supabase project that already ran the old migrations, keep using that project’s migration history, or create a new project and apply only this file there.

## Deploy Edge Function

```bash
supabase functions deploy notify-expense --no-verify-jwt
```

`--no-verify-jwt` allows the **Database Webhook** to call the function with a shared secret header instead of a user JWT.

Set function secrets in the dashboard (Project Settings → Edge Functions) or CLI:

```bash
supabase secrets set \
  WEBHOOK_SECRET=your-long-random-string \
  APNS_AUTH_KEY_PEM="$(cat AuthKey_XXXXX.p8)" \
  APNS_KEY_ID=XXXXXXXXXX \
  APNS_TEAM_ID=XXXXXXXXXX \
  APNS_BUNDLE_ID=bodhija.SplitMate \
  APNS_USE_SANDBOX=1
```

Use `APNS_USE_SANDBOX=0` for TestFlight/App Store builds talking to production APNs.

## Database Webhook (new expense → notify)

1. Supabase Dashboard → **Database** → **Webhooks** → **Create a new hook**.
2. **Table**: `public.expenses`, **Events**: Insert.
3. **Type**: Supabase Edge Functions → select `notify-expense`,  
   **or** HTTP Request to  
   `https://<PROJECT_REF>.supabase.co/functions/v1/notify-expense`  
   with header `Authorization: Bearer <SERVICE_ROLE_KEY>` and `x-webhook-secret: <WEBHOOK_SECRET>` (must match the Edge Function secret).

If you use the Dashboard “Edge Functions” webhook target, add a custom header `x-webhook-secret` with the same value you stored in `WEBHOOK_SECRET`.

The function expects a JSON body shaped like Supabase webhooks: `{ "type": "INSERT", "record": { ...expense row } }`.

## Auth

Enable **Email** (magic link or password) under Authentication → Providers. For magic link, configure redirect URLs for your app’s URL scheme if you add deep linking later.

When signing up with metadata, you can pass `username` in `options.data` from the client; otherwise the trigger generates a username from the email prefix plus an id fragment.

## iOS app: Supabase URL and anon key

The app reads **`SUPABASE_URL`** and **`SUPABASE_ANON_KEY`** from the run environment first, then from **Info.plist** if present. It does not use hard-coded project values (so they are not committed by mistake).

1. In Xcode: **Product → Scheme → Edit Scheme… → Run → Environment Variables**.
2. Add:
   - `SUPABASE_URL` = `https://<YOUR_PROJECT_REF>.supabase.co` (from **Project Settings → API** in the Supabase dashboard)
   - `SUPABASE_ANON_KEY` = the **anon** / **public** key from the same page

If these are missing or still placeholders, the app stops at launch with a clear `preconditionFailure` message instead of failing sign-in with `NSURLErrorDomain -1003` (“hostname could not be found”).
