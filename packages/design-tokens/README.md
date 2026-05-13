# @dripadvisor/design-tokens

Source of truth for colors / typography / spacing used across:

- `apps/ios/` — mirrored in `DripAdvisor/Theme/Theme.swift`
- `apps/chrome-extension/` — referenced in `popup.html` CSS
- `apps/web/` (future) — imported by Tailwind config

## Current tokens (mirror of Theme.swift)

| Token            | Hex (RGB)               | Use                         |
|------------------|-------------------------|-----------------------------|
| `bg`             | `#F9F5ED` (0.976, 0.961, 0.941) | App background          |
| `textPrimary`    | rgba(0,0,0,0.9)         | Body copy                   |
| `textSecondary`  | rgba(0,0,0,0.7)         | Subheads                    |
| `textMuted`      | rgba(0,0,0,0.4)         | Caption                     |
| `textDisabled`   | rgba(0,0,0,0.3)         | Placeholder                 |
| `buttonPrimary`  | rgba(0,0,0,0.8)         | Primary CTA fill            |
| `glass`          | rgba(255,255,255,0.1)   | Card tint                   |
| `glassBorder`    | rgba(255,255,255,0.6)   | Card border                 |
| `error`          | rgba(180,60,60,0.8)     | Destructive                 |

## TODO

- [ ] Export as `tokens.json` (Style Dictionary input)
- [ ] Generate `tokens.swift` + `tokens.css` + `tokens.ts` outputs
- [ ] Wire Theme.swift to read from generated file
