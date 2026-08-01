# Design System: Modern Athletic Heritage & Data Minimalism

## 1. Overview & Creative North Star
The Creative North Star for this system is **"The Stoic Analyst."** This is a high-performance environment designed for elite football coaching, where the prestige of heritage meets the cold precision of modern biometrics. 

To break away from "template" app design, this system rejects rounded corners and soft glows in favor of **Brutalist Precision**. We use intentional asymmetry and extreme typographic scale (massive, condensed data points against expansive negative space) to create an editorial feel that mimics high-end athletic journals. The interface should feel like a custom-machined tool, sharp and expensive.

## 2. Colors & Surface Architecture
The palette is rooted in the deep shadows of the stadium tunnel, punctuated by the cobalt blue of early-2000s sports broadcasting.

### Color Tokens
*   **Surface (Background):** `#0A1929` (Deep Navy)
*   **Primary (Accent):** `#1E88E5` (Cobalt Blue)
*   **Primary Deep:** `#0D47A1` (Cobalt Deep)
*   **On-Surface (Primary Text):** `#F2F6FB` (Off-White)
*   **Tertiary (Negative Data):** `#FF5252` (Bright Red)
*   **Success (Positive Data):** `#4ADE80` (Vibrant Green)

### The Layering Principle (Depth without Shadows)
We prohibit the use of elevation shadows or glows. Depth is achieved strictly through **Tonal Layering**.
*   **Base Layer:** `surface` (#0A1929).
*   **Secondary Sections:** Use `surfaceLow` (#0F1B2D) to define large content areas.
*   **High-Priority Data Cards:** Use `surfaceHigh` (#1A2942) to create a "lifted" effect through color contrast alone.
*   **The "No-Line" Rule:** Do not use borders to define containers. A change in the surface token is the only permissible way to denote a new section.

## 3. Typography
The typographic system relies on the tension between the aggressive, condensed energy of the pitch and the neutral clarity of the tactics board.

*   **Display & Headline (Epilogue/Athletic Sans):** Used for massive data points (e.g., Win %) and section headers. These should be set in All-Caps with tight tracking (-2% to -5%) to evoke a sense of "Modern Athletic Heritage."
*   **Body & Labels (Inter):** Used for all instructional text, player names, and descriptions. Inter provides the "Whoop-style" utility, ensuring that even dense tactical data remains legible.
*   **Scale Contrast:** To achieve an editorial look, a Headline-LG (2rem) should often sit immediately adjacent to a Label-SM (0.6875rem). This high-contrast pairing eliminates the "mid-tier" visual clutter common in generic apps.

## 4. Elevation & Precision
In this system, "Elevation" is a misnomer. We use **Planar Precision**.

*   **Sharp Edges Only:** Every component, from buttons to cards, must use a `0px` border radius. This communicates military-grade discipline.
*   **The 1px Hairline:** While sectioning is done via color shifts, internal list items (e.g., a roster of 22 players) may use a `1px` hairline divider using `chrome` (#5B6A7F) at 30% opacity. It should feel like a surgical incision, not a structural wall.
*   **Negative Space as a Component:** Treat white space as a functional element. "Data Minimalism" requires that for every dense cluster of statistics, there is an equivalent "breathing zone" of pure `surface` color to prevent cognitive overload.

## 5. Components

### Buttons
*   **Primary:** Solid `primary` (#1E88E5) with `on_primary` text. No rounded corners. Text is All-Caps Inter Bold.
*   **Secondary:** Ghost style. No background. `1px` border using `outline`.
*   **Tertiary:** Text-only. Cobalt Blue, underlined with a 1px offset.

### Data Chips (Pill-Shaped)
The *only* exception to the sharp-edge rule. Tags for player positions (e.g., "CDM", "ST") or status must be fully pill-shaped. This provides a "tactical magnet" feel, as if these elements can be moved across a whiteboard. Use `surface_variant` with `on_surface_variant` text.

### Statistics & Performance Metrics
*   **Growth (+):** Subdued Green text, no icons. Use `body-lg` for the value.
*   **Decline (-):** `tertiary` (#FF5252). 
*   **The Hero Metric:** Large-scale `display-lg` numbers. These should be the largest element on the screen, often pushed to the far left or right to create asymmetrical tension.

### Inputs & Forms
*   **Fields:** Flat `surface_container_lowest`. No borders on three sides; only a bottom `1px` hairline in `outline_variant`.
*   **Focus State:** The bottom hairline transitions to `primary` (Cobalt Blue).

## 6. Do’s and Don’ts

### Do
*   **Do** use extreme vertical margins (using spacing `16` or `20`) to separate distinct data modules.
*   **Do** use "Ghost Borders" (low-opacity `outline_variant`) for accessibility only when tonal shifts are insufficient.
*   **Do** keep all icons (if used) strictly 1px stroke weight, sharp corners, no fills.

### Don't
*   **Don't** use border-radius, even for "softness." This app is about the rigors of professional football.
*   **Don't** use gradients, glows, or drop shadows. These are "consumer" tropes; this system is a professional tool.
*   **Don't** center-align long-form data. Use left-aligned "Editorial" grids to maintain a high-end feel.