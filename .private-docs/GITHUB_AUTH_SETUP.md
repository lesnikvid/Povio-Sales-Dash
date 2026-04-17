# GitHub Authentication Setup Guide

Your application has been migrated from Auth0 to GitHub authentication using Supabase Auth. This is completely free and integrates seamlessly with GitHub Pages hosting.

## What Changed

### Removed:
- ❌ Auth0 SDK and dependencies
- ❌ Auth0 client configuration
- ❌ Auth0 JWT token management
- ❌ Complex authentication flow

### Added:
- ✅ Supabase GitHub OAuth authentication
- ✅ Simplified login flow (one function call)
- ✅ Native Supabase auth integration
- ✅ "Sign in with GitHub" button

## Setup Instructions (5 minutes)

### Step 1: Enable GitHub OAuth in Supabase

1. Go to your Supabase project dashboard:
   ```
   https://supabase.com/dashboard/project/jiufnsnxuvhqwzozhlwm
   ```

2. Navigate to **Authentication → Providers**

3. Find **GitHub** in the provider list

4. Click **Enable** on GitHub provider

5. You'll see two fields:
   - **Client ID** (from GitHub)
   - **Client Secret** (from GitHub)

Keep this tab open, we'll fill these in after Step 2.

---

### Step 2: Create GitHub OAuth App

1. Go to GitHub Settings:
   ```
   https://github.com/settings/developers
   ```

2. Click **OAuth Apps** → **New OAuth App**

3. Fill in the form:
   ```
   Application name: Povio Sales Dashboard
   Homepage URL: https://YOUR-GITHUB-USERNAME.github.io/Povio-Sales-Dash
   Authorization callback URL: https://jiufnsnxuvhqwzozhlwm.supabase.co/auth/v1/callback
   ```

   **IMPORTANT**: Replace `YOUR-GITHUB-USERNAME` with your actual GitHub username.

4. Click **Register application**

5. You'll see:
   - **Client ID** (copy this)
   - Click **Generate a new client secret** → **Client Secret** (copy this)

---

### Step 3: Connect GitHub to Supabase

1. Go back to your Supabase tab (Authentication → Providers → GitHub)

2. Paste the values from GitHub:
   - **Client ID**: [paste from GitHub]
   - **Client Secret**: [paste from GitHub]

3. Click **Save**

---

### Step 4: Enable GitHub Pages (if not already done)

1. Go to your repository settings:
   ```
   https://github.com/YOUR-USERNAME/Povio-Sales-Dash/settings/pages
   ```

2. Under **Source**, select:
   - Branch: `claude/import-html-app-9MWX1` or `main`
   - Folder: `/ (root)`

3. Click **Save**

4. Wait 1-2 minutes for deployment

5. Your site will be available at:
   ```
   https://YOUR-GITHUB-USERNAME.github.io/Povio-Sales-Dash
   ```

---

### Step 5: Update OAuth Callback URL (if needed)

If you're using a custom domain or different branch, update the callback URL:

1. Go to GitHub OAuth App settings
2. Update **Authorization callback URL** to match your deployment URL
3. The format should always be:
   ```
   https://jiufnsnxuvhqwzozhlwm.supabase.co/auth/v1/callback
   ```

---

## Testing the Authentication Flow

### Test 1: Login

1. Open your deployed site
2. Click **"Sign in with GitHub"**
3. You should be redirected to GitHub
4. Authorize the app
5. You should be redirected back and logged in

### Test 2: Data Access

1. After login, check your dashboard
2. You should see your goals and whale accounts
3. Try adding a new goal or whale account
4. Data should save correctly

### Test 3: Logout

1. Click the logout button
2. You should be signed out
3. Page should show login screen again

---

## Troubleshooting

### Issue: "Sign in with GitHub" doesn't work

**Solution:**
- Check that GitHub OAuth app is created
- Verify Client ID and Secret are correctly pasted in Supabase
- Ensure callback URL is exactly: `https://jiufnsnxuvhqwzozhlwm.supabase.co/auth/v1/callback`

### Issue: After login, redirected to wrong URL

**Solution:**
- Update the **Homepage URL** in GitHub OAuth app settings
- Make sure it matches your GitHub Pages URL

### Issue: Can't see my data after login

**Possible causes:**
1. **RLS Policies Not Applied**: Run the SQL from `QUICK_FIX.sql` in Supabase
2. **User ID Changed**: Your new GitHub auth creates a new user ID. Your old Auth0 data is still in the database with the old user ID.

**Solution for Old Data:**
If you had data with Auth0 and want to migrate it:

```sql
-- Run this in Supabase SQL Editor
-- Replace 'OLD_USER_ID' with your Auth0 user ID (check in database)
-- Replace 'NEW_USER_ID' with your GitHub user ID (check after first login)

-- Update goals
UPDATE goals SET user_id = 'NEW_USER_ID' WHERE user_id = 'OLD_USER_ID';

-- Update whales
UPDATE whales SET user_id = 'NEW_USER_ID' WHERE user_id = 'OLD_USER_ID';

-- Update whale_notes
UPDATE whale_notes SET user_id = 'NEW_USER_ID' WHERE user_id = 'OLD_USER_ID';
```

To find your new GitHub user ID:
1. Login with GitHub
2. Open browser console (F12)
3. Run: `supabase.auth.getUser().then(console.log)`
4. Look for `user.id` in the output

### Issue: Authentication keeps redirecting in a loop

**Solution:**
- Clear browser cache and cookies
- Try in incognito/private mode
- Check browser console for errors

---

## Security Notes

### Row Level Security (RLS)

Make sure you've applied RLS policies from `QUICK_FIX.sql`:

```sql
-- Verify RLS is enabled
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename IN ('goals', 'whales', 'whale_notes')
AND schemaname = 'public';

-- Should return 3 rows with rowsecurity = true
```

### Client Secret Protection

**IMPORTANT**: Never commit your GitHub Client Secret to your repository. It's only stored in Supabase dashboard.

---

## Benefits of GitHub Auth

### Free Hosting ✅
- GitHub Pages: Unlimited bandwidth (no more Netlify limits!)
- GitHub Auth: Free OAuth (no Auth0 subscription needed)
- Supabase: Free tier with 50,000 monthly active users

### Simpler Codebase ✅
- Removed ~100 lines of Auth0 code
- Single authentication provider
- Native Supabase integration

### Better Developer Experience ✅
- One GitHub account for everything (repo + auth)
- No separate Auth0 dashboard to manage
- Faster authentication flow

---

## Migration Summary

### Code Changes Made:
1. ✅ Removed Auth0 SDK script tag
2. ✅ Replaced `App` component with Supabase auth flow
3. ✅ Removed `auth0Client` state and props
4. ✅ Removed `configureSupabaseAuth()` function
5. ✅ Updated all `user.sub` → `user.id` (Supabase format)
6. ✅ Updated login button to "Sign in with GitHub"

### Manual Steps Required:
1. ⏳ Enable GitHub OAuth in Supabase (Step 1)
2. ⏳ Create GitHub OAuth App (Step 2)
3. ⏳ Connect GitHub to Supabase (Step 3)
4. ⏳ Enable GitHub Pages (Step 4)

---

## Next Steps

1. **Complete setup** using steps 1-4 above (5 minutes)
2. **Test authentication** using the test cases
3. **Migrate old data** if needed (optional)
4. **Verify RLS policies** are working correctly

---

## Questions?

If you run into issues:
1. Check the troubleshooting section above
2. Review Supabase dashboard logs (Authentication → Logs)
3. Check browser console for error messages
4. Verify all URLs match (GitHub Pages URL, callback URL, etc.)

---

**Your app is now ready for free hosting on GitHub with GitHub authentication!** 🎉
