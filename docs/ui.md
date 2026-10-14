Yep — if you mean **text/copy consistency across Lauriva**, there are several things I'd standardize. The UI itself is already visually cohesive; the bigger issue is the **language system**.

### Text consistency improvements

1. **Use one term for the input**
   - Studio: `YOUR TEXT`
   - Forensics: `DOCUMENT TO AUDIT`
   - Humanizer: `DOCUMENT PASSAGE`
   - Pick one system-wide term, e.g. **`YOUR TEXT`** or **`DOCUMENT`**.
   - I'd use **`YOUR TEXT`** because Lauriva isn't limited to documents.

2. **Standardize "AI" terminology**
   You're currently using:
   - `AI Authorship`
   - `AI-LIKELIHOOD`
   - `AI Risk`
   - `AI: 25%`
   - `AI probability`
   
   These sound like different metrics even when they're related.
   
   Better:
   - **AI Likelihood** → primary metric
   - **Human Likelihood** → complementary metric
   - **AI Risk** → only for sentence-level diagnostic risk

3. **Fix this confusing combination**
   > `AI Authorship 25%`  
   > `HUMAN WRITTEN`
   
   That's contradictory at first glance.

   Better:
   **AI Likelihood — 25%**  
   `Mostly human-written`

4. **Don't mix "Originality" and "Source Match"**
   You have:
   - `Originality & Writing Analysis`
   - `Source Match`
   - `0 confirmed duplicate sources`
   - `Originality & Sour...`
   
   Pick a consistent vocabulary:
   
   **Originality**
   - Source Matches
   - Duplicate Content
   - Repeated Phrases
   
   **Writing Analysis**
   - AI Likelihood
   - Sentence Risk
   - Writing Patterns

5. **Standardize capitalization**
   You currently mix:
   - `Originality & Writing Analysis`
   - `AI-LIKELIHOOD`
   - `Run Forensic Scan`
   - `Humanized Output`
   - `HUMAN WRITTEN`
   
   I'd use **Title Case for UI labels**:
   - `AI Likelihood`
   - `Human Written`
   - `Humanized Output`
   - `Run Forensic Scan`
   - `Writing Analysis`

   Reserve ALL CAPS for tiny section labels if you want that visual style:
   - `YOUR TEXT`
   - `ACTIONS`
   - `OUTPUT`

6. **Make metric wording grammatically parallel**
   Instead of:
   > `Semantic Fidelity`  
   > `Content Preserved`
   
   Use either nouns:
   - `Semantic Fidelity`
   - `Content Preservation`
   
   Or descriptive states:
   - `Meaning Preserved`
   - `Content Preserved`

   I'd choose:
   **Semantic Fidelity** + **Content Preserved**

7. **"Forensic" needs one consistent naming hierarchy**
   
   Current:
   - `Forensics`
   - `Forensic Report`
   - `Forensic Dimensions`
   - `Forensic Inspector`
   - `Forensic Scan`
   
   This is actually mostly good. I'd make the hierarchy intentional:
   
   **Forensics**
   → `Forensic Report`
   → `Forensic Dimensions`
   → `Forensic Inspector`

8. **Avoid truncating important labels**
   These:
   - `Originality & Writing Analy...`
   - `Originality & Sour...`
   - `Forensic Inspector...`
   
   make the product feel unfinished.
   
   Give those tabs/headers enough width or shorten the actual copy:
   - `Originality`
   - `Writing Analysis`
   - `Inspector`

9. **"Humanize" should mean one thing**
   You use `Humanize` as:
   - an action
   - a button
   - a report action
   
   That's okay, but distinguish the states:
   
   `Humanize` → action  
   `Humanized Output` → result  
   `Humanized` → status

10. **Standardize sentence terminology**
   The Forensics screen says:
   > `highlighted sentence`
   
   Then:
   > `S1`, `S2`, `S3`, `S4`
   
   Better:
   **Sentence 1**, **Sentence 2**, etc.  
   Or keep `S1` but explicitly call the section:
   **Sentence-Level Analysis**

11. **The 100% sentence scores need clearer wording**
   Overall:
   > `AI: 25%`
   
   Yet every sentence shows:
   > `100%`
   
   A user can easily think the numbers contradict each other.

   Instead of just `100%`, say:
   **High AI Risk**  
   or:
   **AI Pattern: 100%**
   
   Then the metric is clearly different from the document-level AI likelihood.

12. **Humanizer wording is slightly inconsistent**
   You have:
   > `Original vs Humanized`
   
   and:
   > `Original 25% AI-likelihood → Humanized 20% AI-likelihood`
   
   I'd use:
   
   **Before & After**
   
   ```
   Original
   25% AI Likelihood
   
   Humanized
   20% AI Likelihood
   ```

### The copy system I'd use for Lauriva

**Studio**
> YOUR TEXT  
> ACTIONS  
> OUTPUT

**Forensics**
> DOCUMENT TO AUDIT  
> FORENSIC REPORT  
> ORIGINALITY  
> WRITING ANALYSIS  
> SENTENCE-LEVEL ANALYSIS

**Humanizer**
> DOCUMENT TO HUMANIZE  
> WRITING PROFILE  
> AI LIKELIHOOD  
> ORIGINAL VS HUMANIZED  
> HUMANIZED OUTPUT

And for metrics:

> **AI Likelihood — 25%**  
> Mostly human-written

> **Source Matches — 0**  
> No matching sources detected

> **Semantic Fidelity — 93%**

> **Content Preserved — 100%**

The **biggest improvement** I'd make is not changing the visual design — it's establishing a small **Lauriva terminology system** so every screen uses the exact same words for the same concepts. That would make the app feel considerably more polished and product-like.Ahh yes 😭 — **visually**, the screens are already very close, but there are a few inconsistencies that make Lauriva feel like 3 different screens rather than one design system.

### 1. Make spacing/rhythm identical

This is probably the biggest one.

Across Studio, Forensics and Humanizer, standardize:

- Page title → same top margin
- Section label → same gap from title
- Input card → same vertical position/padding
- Section-to-section spacing → same
- Bottom navigation → exact same height/padding
- Horizontal page margins → **30px-ish everywhere**

Right now Forensics becomes much denser because of the report cards, while Humanizer has large empty areas.

**Rule:** every screen should use the same 8pt spacing system.

---

### 2. Standardize card geometry

Your cards are already good, but their shapes vary slightly.

I'd define:

```text
Page horizontal padding: 30
Card radius: 24
Small card radius: 16
Button radius: 16
Card internal padding: 20–24
Section gap: 28–32
```

Then use those values everywhere.

Especially the **input cards** should feel like the exact same component on all three pages.

---

### 3. Your bottom navigation is excellent — make it the absolute anchor

This is one of the strongest parts visually.

Keep:

- same height
- same pill shape
- same icon size
- same selected-state glow
- same selected background
- same spacing
- same label typography

And don't let content visually collide with it.

The Forensics screen gets particularly close to the nav because the report is very long.

I'd add a consistent **bottom content safe area** so the last card/button always ends comfortably above the nav.

---

### 4. Reduce the number of visual "containers"

Forensics has:

> Report card  
> tabs  
> forensic dimensions cards  
> inspector container  
> sentence cards  
> buttons

They're all individually nice, but together there's **a lot of borders**.

It creates a slightly nested-dashboard feeling.

I'd use:

**Level 1 — major card**
- Forensic Report
- Forensic Inspector

**Level 2 — internal cards**
- Dimensions
- Sentence items

**Level 3 — controls**
- tabs/buttons/chips

That hierarchy will make the screen much easier to scan.

---

### 5. Unify the teal treatment

You have several slightly different teal effects:

- teal text
- teal borders
- teal glow
- teal filled buttons
- teal selected states
- teal progress arcs

They're individually good, but establish exactly **three teal usages**:

**Primary**
→ filled button / active CTA

**Accent**
→ icons, section labels, selected navigation

**Glow**
→ only important active/focus elements

Don't let every interactive element glow.

---

### 6. Your red/orange/green diagnostic colors should be semantic

Forensics does this fairly well:

🔴 AI  
🟠 Mixed  
🟢 Human

But the red sentence cards are **very visually dominant**.

I'd make the red background considerably more subtle and let the **border + small badge** communicate risk.

Something like:

```text
Normal card
████████████████

Risk card
╭────────────────╮
│ S1        100% │
│ Technology...  │
╰────────────────╯
```

Rather than making the entire card feel red.

This would make the screen feel more premium.

---

### 7. Humanizer's 20% circle needs the same visual language as Forensics

This is one area I'd definitely tighten.

Forensics:

**25%** → circular visualization

Humanizer:

**20%** → circular visualization

They're conceptually related, but the treatment isn't quite identical.

Make a reusable:

### `MetricRing`

Same:

- diameter
- stroke width
- animation
- glow
- typography
- percentage positioning

Then only change the metric/color/state.

That gives Lauriva a recognizable visual identity.

---

### 8. Humanizer has too much vertical whitespace

This is probably the biggest visual weakness in that screen.

After:

> Writing Profile

you have a large gap before the 20% metric.

Then another relatively large gap before the cards.

I'd tighten it:

```text
Writing Profile
       ↓ 20px
AI Likelihood Ring
       ↓ 24px
Metrics
       ↓ 24px
Original vs Humanized
       ↓ 24px
Humanized Output
```

It'll feel much more intentional.

---

### 9. Studio's Actions carousel needs a little cleanup

The right-side partially visible action card is actually a good indication that it's horizontally scrollable, **but** it looks slightly clipped.

I'd make the interaction intentional:

```text
[ Translate ] [ Fix Grammar ] [ Rewrite ] →
```

with a tiny amount of the next card visible.

That gives a clear carousel affordance.

---

### 10. Typography hierarchy should be locked

I'd define a Lauriva type scale rather than styling each screen independently:

```text
Page title        32 / Bold
Section heading   16 / SemiBold
Card title        18 / SemiBold
Body              16 / Regular
Secondary         14 / Medium
Metric            42–48 / Bold
Micro label       12–13 / SemiBold
```

Your current typography is already close. The important thing is making the **same semantic level always have the same size/weight**.

---

### 11. Icons need one consistent family

You're mostly there, but make sure every icon comes from the same icon system/style.

For example:

- outline icons
- same stroke width
- same visual weight
- same corner treatment

Don't mix a thin icon with a heavy filled icon unless it's intentionally an active-state icon.

---

### 12. One thing I'd actually KEEP

The **dark background + subtle teal glow + glassy dark cards** is working.

Don't over-design it.

Lauriva currently has a nice:

**dark → graphite → teal accent**

identity.

I'd avoid adding gradients everywhere, excessive neon, or more colors. The UI will look more expensive if you **reduce** visual noise rather than adding effects.

### Overall visual consistency

I'd roughly put it at **8.5/10 currently**.

The individual screens look good. The next jump isn't "make it prettier"; it's making a **single Lauriva Design System** and forcing all three screens to obey it.

The biggest 5 changes I'd make:

**① Same spacing grid**  
**② Same card geometry**  
**③ Same metric-ring component**  
**④ Less nested borders on Forensics**  
**⑤ Less empty space on Humanizer**

Those would make the app feel much more like a **single polished product** rather than three polished pages.