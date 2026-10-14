# Privacy Policy for Lauriva: AI Writing Studio

**Effective Date:** October 1, 2026  
**Application:** Lauriva: AI Writing Studio (`com.lauriva.app`)  
**Developer:** Ralein Nova  

---

Welcome to **Lauriva: AI Writing Studio** ("we", "our", or "the App"). We respect your privacy and are committed to protecting it through transparent practices. This Privacy Policy describes how information is handled when you use the Lauriva mobile application.

## 1. Information We Process

* **User Input & Documents:** Text and documents you paste or write in the Studio, Humanizer, or Forensics tools are processed strictly to perform the requested transformations (e.g., rewriting, multi-language translation, humanizing, grammar correction, or AI/plagiarism detection). We do not store, retain, or sell your submitted text, nor do we use your inputs to train proprietary AI models.
* **On-Device Offline Forensics:** Stylometric analysis and on-device neural AI detection run locally on your device via quantized ONNX models without transmitting your content to external analysis servers.
* **Speech & Audio Input:** When you use voice dictation, audio is accessed in real time strictly to transcribe speech into text via your device's native speech recognition. Audio recordings are never saved, stored, or transmitted to our servers.

## 2. Device Permissions Used

* **Microphone (`android.permission.RECORD_AUDIO`):** Required only when you explicitly tap the microphone button for speech-to-text dictation. Audio input ceases as soon as speech recognition stops.
* **Internet Access (`android.permission.INTERNET`):** Used to communicate with user-configured AI cloud providers (e.g. OpenAI, Anthropic, Gemini, Groq) and to query academic/web indexing APIs for literature plagiarism citations.
* **Bluetooth (`android.permission.BLUETOOTH_CONNECT`):** Used optionally to route speech input and audio playback to connected wireless headsets or earbuds.

## 3. API Keys & Third-Party AI Services

Lauriva allows users to optionally connect their own API keys for services such as OpenAI, Anthropic Claude, Google Gemini, Groq, or OpenRouter:
* Your API keys are stored exclusively on your device using hardware-backed encrypted storage (Android Keystore via `flutter_secure_storage`).
* API keys are never transmitted to any central Lauriva server.
* When you trigger a cloud transformation, your prompt is sent directly from your device to the chosen third-party AI provider over TLS/HTTPS, subject to their respective privacy policies.
* **Online source check (plagiarism scans, on by default, can be turned off in the scan settings):** to find matching sources, the app sends a few short excerpts (about 25 words each, with emails, links and long numbers removed) from the text you scan, never the whole document, directly from your device to public search services: Wikipedia, Wikinews, Bing, Brave Search, Exa, DuckDuckGo, OpenAlex, Crossref, DOAJ, PubMed, Europe PMC, Semantic Scholar, arXiv, Stack Exchange and Hacker News (Algolia). These services receive your IP address and the excerpt, subject to their own privacy policies. When verifying matches, the app may also ask Jina Reader (r.jina.ai) or Exa to fetch the public pages that the search already returned, so those services learn the URLs of matched public pages (not your text), and it may fetch a page directly from your device. With online search off, your text is never sent anywhere and scans use only the offline source index. That index (about 24 MB, hashed fingerprints only, no source text) is downloaded once over Wi-Fi from a GitHub release and kept on your device; GitHub sees your IP address for that download, but none of your text.

## 4. Data Retention & Sharing

Lauriva does not operate centralized user databases, does not require an account or login, and does not sell or share personal data with data brokers or advertising networks.

## 5. Children’s Privacy

Lauriva is not targeted at children under the age of 13, and we do not knowingly collect personal information from children.

## 6. Changes to This Policy

We may update our Privacy Policy periodically. Any updates will be reflected on this page with an updated effective date.

## 7. Contact Information

If you have questions or suggestions regarding this Privacy Policy, please contact:
* **Developer:** Ralein Nova
* **Project:** Lauriva: AI Writing Studio
* **GitHub:** [https://github.com/Ralein/Lauriva-Mobile](https://github.com/Ralein/Lauriva-Mobile)
