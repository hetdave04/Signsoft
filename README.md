# SignSoft — Production Deployment Guide

## Files in This Package

```
signsoft/
├── index.html                          ← The full app (open this in browser)
├── config.js                           ← Your credentials go here
├── vercel.json                         ← Vercel deployment config
└── supabase/
    ├── schema.sql                      ← Run once in Supabase SQL Editor
    └── functions/
        └── send-email/
            └── index.ts               ← Email Edge Function (optional)
```

---

## Deploy in 5 Steps

### Step 1 — Fill in config.js
Open `config.js` and replace the placeholder values:

```js
window.SIGNSOFT_CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT_REF.supabase.co',  // ← your URL
  supabaseKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6...',       // ← your anon key
  resendKey:   're_xxxx',                                 // ← optional
};
```

Get your URL and key from:
**Supabase Dashboard → Settings → API**

---

### Step 2 — Set up Supabase (one time, ~10 min)

**A. Create project**
- Go to https://supabase.com → New Project
- Pick a name, password, and region. Wait ~2 min.

**B. Run the database schema**
- Supabase → SQL Editor → New Query
- Open `supabase/schema.sql`, paste everything, click Run
- You should see: "Schema created successfully!"

**C. Create storage bucket**
- Supabase → Storage → New Bucket
- Name: `documents` | Type: Private | Click Create
- Go to Policies on that bucket and add:

  **For INSERT (upload):**
  ```sql
  (auth.uid()::text = (storage.foldername(name))[1])
  ```

  **For SELECT (download):**
  ```sql
  (auth.role() = 'authenticated')
  ```

**D. Enable Realtime (for live notifications)**
- Supabase → Database → Replication
- Toggle ON the `notifications` table

---

### Step 3 — Deploy to Vercel (~5 min)

**Option A — Drag and drop (easiest)**
1. Go to https://vercel.com → Log in (free account)
2. Click "Add New Project" → "Deploy without Git"
3. Drag the entire `signsoft` folder into the upload area
4. Click Deploy
5. Your site is live at `https://signsoft-xxxx.vercel.app`

**Option B — GitHub (recommended for updates)**
1. Create a GitHub account at https://github.com
2. Create a new repository named `signsoft`
3. Upload all files in this folder to the repository
4. Go to https://vercel.com → New Project → Import from GitHub
5. Select your `signsoft` repo → Deploy
6. Future updates: just push to GitHub, Vercel auto-deploys

---

### Step 4 — Add your custom domain (~5 min)

1. Buy a domain at https://namecheap.com (e.g. yourbrand-sign.com, ~$10/year)
2. In Vercel → Your Project → Settings → Domains
3. Add your domain (e.g. `sign.yourbrand.com`)
4. Vercel shows you 2 DNS records to add
5. Go to your domain registrar → DNS settings → add those records
6. Wait 5–15 min for DNS to propagate
7. Vercel automatically adds SSL certificate (HTTPS) — free

---

### Step 5 — Set up email sending (optional, ~10 min)

Without this, signing links are shown on-screen instead of being emailed.

**A. Get a Resend account**
- Go to https://resend.com → Sign up free (3,000 emails/month)
- Add your domain (e.g. `mail.yourbrand.com`) and verify DNS
- Copy your API key

**B. Install Supabase CLI**
```bash
npm install -g supabase
```

**C. Link your project**
```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
```
(Project ref is the part of your URL: `https://YOUR_PROJECT_REF.supabase.co`)

**D. Deploy the email function**
```bash
cd signsoft
supabase functions deploy send-email --project-ref YOUR_PROJECT_REF
```

**E. Set secrets**
```bash
supabase secrets set RESEND_API_KEY=re_your_key_here --project-ref YOUR_PROJECT_REF
supabase secrets set FROM_EMAIL=noreply@yourdomain.com --project-ref YOUR_PROJECT_REF
```

**F. Update config.js**
```js
resendKey: 're_your_key_here',
```

---

## First Login

After deploying, go to your URL and:
1. Click "Create Account" on the login page
2. Sign up with your email and password
3. Make yourself Super Admin by running this in Supabase SQL Editor:

```sql
UPDATE profiles SET role = 'super_admin' WHERE email = 'your@email.com';
```

---

## Cost Summary

| Service | Free Limit | Cost if Exceeded |
|---|---|---|
| Vercel (hosting) | 100 GB bandwidth/month | $20/month |
| Supabase (DB + Auth + Storage + Functions) | 50,000 users, 500 MB DB, 1 GB storage | $25/month |
| Resend (email) | 3,000 emails/month | $20/month for 50,000 |
| Domain | — | ~$10–15/year |

**For under 1,000 users: $0/month**

---

## Troubleshooting

**Blank page or nothing loads**
→ Open browser DevTools (F12) → Console tab → look for red errors
→ Most likely: wrong Supabase URL or key in config.js

**"Failed to fetch" errors**
→ Check your Supabase URL starts with `https://` and ends with `.supabase.co`
→ Make sure you used the **anon** key, not the service_role key

**Can't upload files**
→ The `documents` bucket in Supabase Storage doesn't exist yet — create it (Step 2C above)
→ Or bucket policies are missing — add the INSERT and SELECT policies

**Notifications not updating live**
→ Enable Realtime on the `notifications` table (Step 2D above)

**Emails not sending**
→ Edge Function not deployed — follow Step 5
→ Or wrong RESEND_API_KEY — verify at resend.com dashboard

**Face verification not working**
→ Camera permission denied — allow camera in browser settings
→ face-api.js model failed to load — check internet connection, try refreshing
→ You can always click "Skip Verification" — it logs as skipped in audit trail

**Row Level Security errors in console**
→ Re-run the full `schema.sql` — the RLS policies weren't created
→ In Supabase SQL Editor, scroll to the CREATE POLICY sections and run them individually

**Can't sign up — "User already registered"**
→ The email is already in Supabase Auth — use "Sign In" instead

---

## Support

If you hit an issue not listed here, go to:
- https://supabase.com/docs — Supabase documentation
- https://resend.com/docs — Resend documentation
- https://vercel.com/docs — Vercel documentation
