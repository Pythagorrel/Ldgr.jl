# Measurements: Source Serif 4 SemiBold and Piazzolla SemiBold (VectorCraft, size 100, outlined)

Method: set each font at size 100, `text.fonts` says status "exact" for Regular and SemiBold of both.
Outlined words and single letters, read anchors with `document.node`, and read group bounds
with `inspect_document`. All numbers are points at size 100; "H" is the cap height.
Weight check: the weight IS applied. L stem Regular vs SemiBold: Source Serif 4 9.5 -> 13.0 (0.142 H -> 0.197 H);
Piazzolla 8.0 -> 12.0 (0.123 H -> 0.185 H).

| measure | Source Serif 4 SemiBold | Piazzolla SemiBold |
|---|---|---|
| cap height H (L, flat) | 66.4 | 65.2 |
| stem width (L, D, R) | 12.9-13.5, take 13.1 = **0.197 H** | 11.8-12.6 (slanted edge), take 12.1 = **0.186 H** |
| thin stroke, D/R top arm, L foot | 5.1 = 0.077 H | 7.6-7.7 = 0.117 H (low contrast) |
| thinnest feature, serif slab edge | 4.7 = **0.071 H** | 4.0 = **0.061 H** |
| D bowl right side (thick) | 13.9 | 12.7 |
| waist: R bowl's lower stroke, centre above baseline | 33.1 = **0.498 H** (stroke 114.4-119.4) | 31.05 = **0.476 H** (stroke 7.5 thick) |
| waist: G crossbar top above baseline | 32.1 = 0.483 H | 33.3 = 0.511 H |
| overshoot G top / bottom | 1.7 / 1.7 (0.026 H) | 1.1 / 0.9 (0.017 / 0.014 H) |
| overshoot D, L | none | none |
| R leg bottom | 1.2 below baseline (0.018 H) | none |
| layout advance L / D / G / R | 58.9 / 70.8 / 67.9 / 66.6 | 59.5 / 73.5 / 70.7 / 70.8 |
| ink left offset from origin L / D / G / R | 3.9 / 3.9 / 4.1 / 3.9 | 2.9 / 2.9 / 4.7 / 2.9 |
| ink width L / D / G / R | 51.7 / 62.8 / 62.3 / 61.7 | 53.2 / 65.9 / 63.1 / 67.1 |
| ink width in H (L / D / G / R) | 0.78 / 0.95 / 0.94 / 0.93 | 0.82 / 1.01 / 0.97 / 1.03 |
| stem-left edge from ink left (L, D, R) | +8.3 | +10.3 to +10.9, take 10.5 |

Notes
- Advances are the layout-box widths. Letters are placed one by one by their ink, so advances are only reference.
- Natural ink gaps in the typed word (Source Serif 4): L-D 5.9, D-G 9.5, G-R 4.4 (uneven, as usual for caps).
- The baseline is exact (L, D, R flat on the baseline); no baseline error for either font.
