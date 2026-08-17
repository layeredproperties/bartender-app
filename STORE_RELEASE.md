# Shipping Tip Out to the App Store

A checklist you can work through in order. Anything marked **[you]** has
to be done by a human in a browser; anything marked **[terminal]** is a
command you run from the project folder.

App identity, already configured:

| | |
|---|---|
| Bundle ID | `com.layeredproperties.tipout` |
| Home screen name | Tip Out |
| Store listing name | Tip Out |
| Version | 1.0.0 (build 1) |

---

## Part 1 — Apple Developer Program **[you]**

Budget 1–2 days; approval is not instant.

1. Your Apple ID must have **two-factor authentication** switched on
   first, or enrollment will refuse to start.
   Check at <https://appleid.apple.com> → Sign-In and Security.
2. Enroll at <https://developer.apple.com/programs/enroll/> as an
   **Individual**. $99/year.
   - The fastest route is the **Apple Developer app on an iPhone** —
     it verifies your identity with Face ID and usually clears in under
     a day. The web form can take longer.
   - No website and no company-domain email are needed. Those are
     Organization requirements; an Individual enrolment needs only an
     Apple ID with two-factor auth.
3. Wait for the approval email.
4. Once approved, get your **Team ID**: <https://developer.apple.com/account>
   → Membership details. It looks like `A1B2C3D4E5`. Send it to me and
   I'll wire it into the project so command-line builds work.

> You do **not** need to manually register the bundle ID or create
> certificates. Xcode's automatic signing does both the first time you
> build.

**Decided: Individual.** An Individual enrolment publishes your verified
legal name as the seller on the App Store listing. That was weighed and
accepted for this app. The alternative — an Organization enrolment,
which shows *Layered Properties LLC* instead — remains available using
the LLC's existing D-U-N-S number, but only if chosen **before** paying:
Apple ties the seller identity to the enrolment, and switching later
means a support request Apple may decline.

Everything else in this repo already carries the Layered Properties name
rather than a personal one — bundle ID, copyright string, commit
identity, and the privacy policy contact.

---

## Part 2 — Privacy policy — DONE ✅

Apple will not accept the submission without a public URL. The policy is
live and verified (HTTP 200):

> **https://layeredproperties.github.io/bartender-app/PRIVACY**

Served by GitHub Pages from `PRIVACY.md` on `main`. Editing that file and
pushing republishes it within a minute or two. Paste this URL into the
Privacy Policy URL field in Part 5.

Support URL (also required) can be the repo itself:
`https://github.com/layeredproperties/bartender-app`

---

## Part 3 — Sign the app in Xcode **[you, once]**

1. **[terminal]** `open ios/Runner.xcworkspace`
   (the *workspace*, not the `.xcodeproj`).
2. In the left sidebar click the blue **Runner** project at the top.
3. Select the **Runner** target → **Signing & Capabilities** tab.
4. Tick **Automatically manage signing**.
5. Set **Team** to your name (it appears once Part 1 is approved).
6. Confirm **Bundle Identifier** reads `com.layeredproperties.tipout`.

Xcode will create the certificate and provisioning profile on its own. A
brief red error while it does this is normal; it clears within a few
seconds.

---

## Part 4 — Build and upload **[terminal]**

```bash
flutter clean
flutter build ipa
```

This produces `build/ios/ipa/tip_out.ipa`. Then either:

**Option A — Transporter (simplest).** Install *Transporter* free from
the Mac App Store, sign in, drag the `.ipa` in, click **Deliver**.

**Option B — Xcode.** `open build/ios/archive/Runner.xcarchive`, then
**Distribute App** → **App Store Connect** → **Upload**.

After upload, the build takes 5–15 minutes to finish processing before it
appears in App Store Connect. You'll get an email when it's ready.

### Later versions

Bump the version in `pubspec.yaml` before every upload — Apple rejects a
build number it has already seen:

```yaml
version: 1.0.1+2    # marketing version + build number
```

---

## Part 5 — Create the listing **[you]**

At <https://appstoreconnect.apple.com> → **My Apps** → **+** → **New App**.

- **Platform**: iOS
- **Name**: `Tip Out` (must be unique across the entire App Store —
  see the note below if it's taken)
- **Primary language**: English (U.S.)
- **Bundle ID**: pick `com.layeredproperties.tipout` from the dropdown
- **SKU**: any private string, e.g. `tipout-001`
- **User Access**: Full Access

Then fill in these sections:

### Screenshots
Required: **iPhone 6.9"** — 1290 × 2796 or 1320 × 2868 px, 3 to 10 images.
Because the app currently ships for iPad too, you will **also** need
**iPad 13"** shots at 2064 × 2752. (See "Open decision" below — dropping
iPad support removes this requirement entirely.)

Capture them from the Simulator: `⌘S` saves a correctly-sized PNG to your
Desktop. I can automate this whole step — just ask.

### Description
Draft to start from:

> Split your shift's tips in seconds.
>
> Tip Out does the math bartenders actually do: separate credit card and
> service charge pools, an equal or hours-based split, and a barback
> tip-out taken proportionally so nobody covers more than their share.
> Every payout is broken out into credit card and service charge amounts,
> ready to enter straight into your POS.
>
> • Equal or hourly splits
> • Barback tip-out as a flat amount, a % of tips, or a % of sales
> • Saves a running CSV tip log you can open or export any time
> • Share a shift with a coworker, who can import it into their own log
> • Adjustable text size
> • Works entirely offline — no account, no tracking

### Keywords
`tip out,bartender,tips,server,gratuity,shift,split,barback,restaurant,bar`

### Other fields
- **Support URL**: your GitHub repo URL is acceptable
- **Privacy Policy URL**: from Part 2
- **Category**: Primary `Business`, Secondary `Finance`
- **Age Rating**: answer No to everything → 4+
- **Price**: Free (or set a tier)

### App Privacy — the important one
**App Privacy** → **Get Started** → answer **"No, we do not collect data
from this app."** That is accurate: the app has no network access at all.
This single answer is what usually trips people up, and for this app it's
genuinely a one-click section.

---

## Part 6 — Submit **[you]**

1. In the version page, scroll to **Build** and pick the build you
   uploaded.
2. **Export Compliance**: already declared in `Info.plist`
   (`ITSAppUsesNonExemptEncryption = false`), so you shouldn't be asked.
   If you are, the answer is **No**.
3. Click **Add for Review** → **Submit for Review**.

Review typically takes 24–48 hours. If it's rejected, the reason appears
in App Store Connect under Resolution Center — rejections are routine and
usually a one-line fix, not a verdict on the app.

---

## Open decision: iPad support

The project currently builds for iPhone **and** iPad
(`TARGETED_DEVICE_FAMILY = "1,2"`). That means:

- You must supply a second set of iPad screenshots.
- Apple reviews the app on an iPad, and layout problems there can cause
  a rejection.

Dropping to iPhone-only is a one-line change and removes both. The app
still runs on iPad in iPhone compatibility mode. Say the word either way.

---

## Appendix — Google Play, when you're ready

The Android side is configured but needs two things first:

1. **Install Android Studio** — `flutter doctor` currently can't find an
   Android SDK, so no Android build is possible yet. Install it, open it
   once, let it download the SDK, then run
   `flutter doctor --android-licenses` and accept.

2. **Create the upload keystore.** This file signs every Android release
   forever — if you lose it you cannot update your own app. Back it up
   somewhere permanent.

   ```bash
   keytool -genkey -v -keystore ~/tipout-upload-key.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

   Then create `android/key.properties` (already gitignored):

   ```properties
   storePassword=<the password you just typed>
   keyPassword=<same password>
   keyAlias=upload
   storeFile=/Users/<your-username>/tipout-upload-key.jks
   ```

   Build with `flutter build appbundle` → `build/app/outputs/bundle/release/app-release.aab`.

3. **Register** at <https://play.google.com/console> ($25 one-time).

> **Plan around this:** new personal Play accounts must run a **closed
> test with 12 testers for 14 consecutive days** before they're allowed
> to publish publicly. Start that clock as early as you can — it's the
> long pole in the Android timeline, not the code.

The 512 × 512 Play Store icon is already generated at
`assets/icon/store_icon_512.png`. You'll also need a 1024 × 500 feature
graphic.
