# Lauriva: 10/10 Google Play Store Production & Deployment Guide

This document provides the complete, end-to-end blueprint to take **Lauriva** from the current codebase to a live, verified release on the **Google Play Store**.

---

## Table of Contents
1. [Pre-Flight Verification Checklist](#1-pre-flight-verification-checklist)
2. [Application Identity & Versioning](#2-application-identity--versioning)
3. [Android Keystore Generation & Release Signing](#3-android-keystore-generation--release-signing)
4. [Building the Production Android App Bundle (.aab)](#4-building-the-production-android-app-bundle-aab)
5. [Google Play Console Setup](#5-google-play-console-setup)
6. [Data Safety Form Declarations (Mandatory)](#6-data-safety-form-declarations-mandatory)
7. [IARC Content Rating Questionnaire](#7-iarc-content-rating-questionnaire)
8. [Store Listing Copy & Creative Assets](#8-store-listing-copy--creative-assets)
9. [Release Rollout Strategy (Internal → Closed → Production)](#9-release-rollout-strategy-internal--closed--production)

---

## 1. Pre-Flight Verification Checklist

Run these commands from the project root to ensure zero static issues and complete test passing:

```bash
# 1. Ensure clean dependencies
flutter pub get

# 2. Verify static analysis (Must return "No issues found!")
flutter analyze

# 3. Verify complete unit and widget test suite (Must pass 30/30 tests cleanly)
flutter test
```

---

## 2. Application Identity & Versioning

### A. Unique Application ID (Package Name)
Google Play requires a globally unique reverse-domain package name.
In `android/app/build.gradle.kts`:
```kotlin
defaultConfig {
    // If releasing under your own organization or domain, update this:
    applicationId = "com.Lauriva.app.Lauriva" // Or e.g. "com.yourdomain.Lauriva"
    minSdk = flutter.minSdkVersion
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
}
```

### B. Incrementing Version for New Builds
In `pubspec.yaml`:
```yaml
version: 1.0.0+1
```
- `1.0.0` is the user-facing `versionName`.
- `+1` is the internal integer `versionCode`. **Every subsequent release submitted to Play Store MUST increment this integer** (e.g. `+2`, `+3`).

---

## 3. Android Keystore Generation & Release Signing

### Step 1: Generate your Private Keystore
Run the following command in your terminal to create a 2048-bit RSA keystore:

```bash
keytool -genkey -v -keystore ~/Lauriva-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias Lauriva-release
```

You will be prompted for:
1. Keystore password (choose a strong password and save it in your password manager).
2. Developer identity questions (Name, Organization, City, Country).
3. Confirmation (`yes`).

> [!CAUTION]
> **Backup your keystore!** If you lose `Lauriva-release-key.jks` or forget the password, you will **never** be able to update your app on the Google Play Store.

---

### Step 2: Configure `key.properties`
Create a file named `android/key.properties` (this file is ignored by Git in `.gitignore`):

```properties
keyAlias=Lauriva-release
keyPassword=YOUR_KEYSTORE_PASSWORD
storeFile=/absolute/path/to/Lauriva-release-key.jks
storePassword=YOUR_KEYSTORE_PASSWORD
```

*Note: Lauriva's `android/app/build.gradle.kts` is already pre-configured to automatically load `key.properties` when building in release mode.*

---

## 4. Building the Production Android App Bundle (.aab)

Google Play requires the **Android App Bundle (.aab)** format for all new apps. App Bundles allow Google Play to generate device-optimized APKs for each user's CPU architecture and screen density.

### Execute Production Build Command:

```bash
flutter build appbundle --release
```

### Build Output:
Upon completion, your release bundle will be located at:
```text
build/app/outputs/bundle/release/app-release.aab
```

### Verify ProGuard / R8 Bytecode Optimization:
Lauriva includes production rules in `android/app/proguard-rules.pro` that automatically:
- Obfuscate Dart native embeddings and plugins.
- Strip unused Android resources (`isShrinkResources = true`).
- Protect native speech and secure storage reflection entry points.

---

## 5. Google Play Console Setup

1. Log in to [Google Play Console](https://play.google.com/console).
2. Click **Create app**:
   - **App name:** `Lauriva - AI Writing & Speech`
   - **Default language:** `English (United States)`
   - **App or game:** `App`
   - **Free or paid:** `Free`
3. Complete the **Set up your app** tasks on the Dashboard:
   - **Privacy Policy** (Mandatory)
   - **App Access** (Lauriva does not require credentials to use; select *"All functionality is available without special access"*).
   - **Ads:** Select *"No, my app does not contain ads"*.
   - **Target Audience:** Select **18 and over** (recommended for AI generation tools).

---

## 6. Data Safety Form Declarations (Mandatory)

Because Lauriva uses microphone permissions (`RECORD_AUDIO`) and sends text prompts to LLM endpoints, you must declare the following in the Play Console **Data safety** section:

### A. Audio Data:
- **Is audio collected?** Select **Yes** (Speech dictation).
- **Is this data processed ephemerally?** Select **Yes** (Audio is converted to text in real time on the device; raw audio recordings are **not** saved or stored on remote servers).
- **Is audio shared with third parties?** Select **No**.
- **Is data encrypted in transit?** Select **Yes**.
- **Can users request data deletion?** Select **Yes** (Users can clear history and text locally at any time).

### B. User Content / Text:
- **Data collected:** User text input and prompt transformations.
- **Purpose:** App functionality (writing assistant features, translation, grammar fixing).
- **Storage:** Text history is stored locally on the user's device in private app storage. When processed via cloud LLMs (e.g. Groq, OpenRouter), requests are sent via HTTPS with end-to-end transport encryption.

---

## 7. IARC Content Rating Questionnaire

In the Play Console **Content rating** section:
1. Category: **Utility, Productivity, Communication or Other**.
2. **Violence, Sex, Hate Speech:** Select **No** for all questions.
3. **User Content Sharing:** Select **No** (It is a local workspace, not a social network).
4. **Online Content / AI Generation:**
   - Does the app feature AI content generation? Select **Yes**.
   - Does the app filter content? Select **Yes** (Lauriva leverages provider-level safety filters and system prompt safety boundaries).

---

## 8. Store Listing Copy & Creative Assets

### A. Store Metadata Copy

#### **App Title** (30 characters max):
```text
Lauriva: AI Speech & Writing
```

#### **Short Description** (80 characters max):
```text
Voice dictation, anti-AI humanizer, tone studio & real-time writing assistant.
```

#### **Full Description** (Up to 4000 characters):
```markdown
Elevate your daily writing and voice dictation with Lauriva — the luxury AI writing assistant and speech studio designed for professionals, creators, and students.

Lauriva combines real-time microphone dictation, on-device stylometry analysis, and multi-model AI inference into a single dark glassmorphic workspace.

KEY FEATURES:

🎙️ REAL-TIME VOICE STUDIO
Dictate your thoughts naturally with an organic audio visualizer. Lauriva transcribes your speech instantly into clean, workable text.

⚡ REAL-TIME TOKEN STREAMING
Watch your transformed text stream in word-by-word with zero wait times. Cancel or tweak generation on the fly with one tap.

🛡️ ANTI-AI "HUMANIZE" ENGINE
Eliminate repetitive AI tells, robotic corporate cliches, and metronomic sentence structures while preserving 100% of your original facts, names, and meaning.

🔬 ON-DEVICE PLAGIARISM & STYLOMETRY DETECTOR
- Burstiness Analysis: Detects synthetic sentence length uniformity.
- Lexical Diversity: Evaluates vocabulary richness using Guiraud's R index.
- N-Gram Repetition Audit: Flags formulaic academic and web boilerplates offline.

✨ MULTI-TONE & STYLE SHAPING
Transform your text instantly with 13 built-in modes:
- Executive, Witty, Assertive, Empathetic, and Storytelling styles
- Concise condensation and grammar fixes
- Multi-lingual translation supporting English, Tamil, Spanish, French, German, Hindi, and Japanese

🌐 MULTI-PROVIDER FREEDOM
Works out of the box with zero setup using Pollinations.ai, or connect your own API keys for Groq, OpenRouter, Google Gemini, and custom OpenAI-compatible endpoints.

🔒 PRIVACY & HARDWARE SECURITY
Your API keys are encrypted in your device's native hardware Keystore. Your data remains strictly in your hands.
```

---

### B. Required Graphical Assets

| Asset | Dimensions | Format | Notes |
| :--- | :--- | :--- | :--- |
| **App Icon** | 512 × 512 px | 32-bit PNG | Must match `assets/images/logo.png` with no transparent background. |
| **Feature Graphic** | 1024 × 500 px | JPEG or 24-bit PNG | Showcase the dark glassmorphic UI, brand title, and "Voice & AI Studio". |
| **Phone Screenshots** | Min 2, max 8 (e.g. 1080 × 2400 px) | JPEG or PNG | Capture Zone 1 (Input), Zone 2 (Actions), and Zone 3 (Streaming Output). |

---

## 9. Release Rollout Strategy (Internal → Closed → Production)

### Phase 1: Internal Testing Track
1. Navigate to **Testing** → **Internal testing** in Google Play Console.
2. Create a new release and upload `build/app/outputs/bundle/release/app-release.aab`.
3. Add internal testers (email list).
4. Testers install the build via the Play Store link to verify:
   - Microphone permission prompts on Android 12, 13, and 14+.
   - Offline on-device plagiarism check works without network.
   - LLM streaming responses render smoothly without UI lag.

### Phase 2: Closed Beta Track
1. Roll out to a broader group of 20+ testers for at least 14 days (mandatory for new personal developer accounts).
2. Gather crash logs in **Android Vitals** (Lauriva's `runZonedGuarded` and `PlatformDispatcher` will log any uncaught exceptions to vitals).

### Phase 3: Production Release
1. Promote the approved build from Closed Testing to **Production**.
2. Select rollout percentage (e.g. 20% on Day 1, scaling to 100% over 5 days).
3. Monitor crash rates and user ratings in the Play Console.
