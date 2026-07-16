# PaperTrail v2 — Animation Spec
Companion to DESIGN_LANGUAGE.md. All curves in SwiftUI terms; prototype reference: `PaperTrail v2 Prototype.html`.

Global rule: animations run **once, on first appearance** — nothing loops, nothing idles. Motion always means "something changed."

## Curves
- `archiveEase` = cubic-bezier(.2,.7,.3,1) → `Animation.timingCurve(0.2,0.7,0.3,1)`
- `sheetEase` = cubic-bezier(.2,.8,.25,1)
- `stampEase` = cubic-bezier(.2,.9,.3,1.3) (slight overshoot)

## 1. Navigation
| Motion | Spec |
|---|---|
| Push | translateX 34→0 + fade, 280ms archiveEase |
| Pop | translateX −26→0 + fade, 260ms |
| Sheet (soft-ask, paywall) | translateY 112%→0, 420ms sheetEase; dim 0→.72 over 280ms |

## 2. Plus band (Settings, S1)
- Foil **sheen sweep**: 70pt highlight, skew −18°, sweeps L→R over 1.4s, delay 0.8s after screen appear. Runs ONCE PER INSTALL (persist flag). Never on subsequent visits.

## 3. Paywall (P1 certificate)
1. Sheet rises (spec above); certificate content static — the document itself is the hero.
2. On BUY: button label → "Confirming with the App Store…" (opacity .7).
3. On success (~900ms later): **MEMBER ✓ stamp** slams onto certificate — scale 2.4→0.92→1.05→1 with rotate −16°→−3°, 500ms stampEase, on 88%-opaque paper chip. Haptic: `.success`.
4. 1.2s later: paywall dismisses, Settings appears, library card **re-strikes in gold**.

## 4. Gold strike (P3 member card)
- Card enters with rotateY 90°→0 + scale .96→1 + fade, 550ms archiveEase (a card being turned over / re-struck).
- Toast: "Your card has been struck in gold." Member № assigned and shown immediately.

## 5. Coverage ring (W2)
- Arc: strokeDashoffset full→target, 900ms archiveEase, 250ms delay after push.
- Center number counts 0→N months, ~70ms/step, finishing with the arc.
- Runs on every visit to the passport (it's the point of the page).

## 6. Soft-ask (N1)
- Paper sheet rises 420ms; example notification banner **drops in** (translateY −16→0 + fade, 400ms, 350ms delay) — the sample note arriving.
- "Yes, notify me" → real `UNUserNotificationCenter` prompt. Either outcome → toast, sheet dismisses.

## 7. Toasts
- Dark blur pill, bottom 108pt, fade+scale .985→1, 200ms in; auto-dismiss 2.2s.

## 8. Micro-interactions
- FAB press: scale .88, spring back `cubic-bezier(.34,1.56,.64,1)` 180ms.
- Copy serial: no animation on the row; toast confirms. Haptic `.light`.
- Toggles: iOS default spring, sage tint.

## 8b. Plan picker (paywall)
- Selection: border + inset ring snap, 150ms ease-out; fine print crossfades 180ms. No layout shift between plans.

## 9. Lapse (subscription end)
- Gold card crossfades back to cream over 600ms on next Settings visit — no drama, no red.

## Don'ts
- No parallax, no looping shimmer, no pulsing CTAs, no paywall countdowns, no trial-ending scare screens.
- Reduce Motion: replace all translations with 200ms crossfades; skip sheen and stamp overshoot.
