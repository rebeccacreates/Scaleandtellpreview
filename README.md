# Scale & Tell · V3.21

Reptile care journal (installable web app) by Herps & Hers. Hosted on GitHub Pages, accounts and sync on Supabase.

## Files
- `index.html` – page markup
- `app.js` – app code (readable, formatted)
- `styles.css` – styles
- `assets/` – artwork, care-guide pages, species portraits (previously packed inside index.html)
- `icon-*.png`, `manifest.webmanifest` – Oro app icon for iPhone and Android
- `sw.js` – reminder notifications + fast loading of the app's own files (never caches account data)
- `privacy.html`, `deletion.html` – draft policy pages
- `supabase/` – database migrations and the `care-push` reminder function (not used by the website itself)

## What changed in V3.21
- Everything from the V3.21 working draft (welcome slides, signup cleanup, Founding Keeper menu, install guide, notification fixes, screenshot reading, urgent-care resource)
- Oro app icon; greeting is "Welcome ♡"; Due Today shows a calendar with a checkmark; tile numbers aligned on small phones
- Screenshot reader: pick the reptile, read on the phone, review every row, confirm before anything is added
- Sync: every record has a permanent ID; deletions and edits carry over between devices automatically; an edit made on two devices keeps the newest and puts the other in Recently Deleted
- Reminder time is account-wide (same on every signed-in device)
- App loads about 1.4 MB instead of 10 MB
- INKBIRD model link removed; small escaping fix on Edit Profile
