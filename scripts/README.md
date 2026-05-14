# scripts/

Repo automation scripts.

## sync-screens-to-notion.mjs

Uploads `apps/ios/screens/NN-*.png` into the Notion **DripAdvisor — iOS Screens** page using Notion's native file upload API (single-part, since screens are < 20 MB). For each PNG, drops an image block right under the matching `## NN — …` heading.

**Idempotent**: each image block carries a caption marker (`auto:NN-foo.png`). Re-runs delete the prior block and append a fresh one — no duplicates.

### One-time setup

1. **Create a Notion integration**
   - https://www.notion.so/profile/integrations → **+ New integration**
   - Type: Internal · Workspace: yours · Name: `dripadvisor-screens-sync`
   - Capabilities: Read content, Update content, Insert content
   - Copy the **Internal Integration Secret** (`ntn_…`)

2. **Invite the integration to the screens page**
   - Open https://www.notion.so/35fb438d4d5681518557c5c1d6a66e03
   - `…` menu → **Connections** → add `dripadvisor-screens-sync`

3. **Install deps**
   ```bash
   cd scripts
   npm install
   ```

### Run

```bash
NOTION_API_KEY=ntn_… npm run sync-screens
```

Output:

```
Found 13 screenshots in /…/apps/ios/screens
Page has 47 top-level blocks
→ 01-avatar-setup.png
   uploading 0.78 MB
→ 02-photo-picker.png
   uploading 1.92 MB
…
Done.
```

### Re-capturing screens

After grabbing fresh screenshots:

```bash
make ios-build && # rebuild
# (use the simulator + ios-simulator-mcp to capture into apps/ios/screens/NN-*.png)
NOTION_API_KEY=ntn_… npm run sync-screens
```

### Env overrides

| Var              | Default                                              |
|------------------|------------------------------------------------------|
| `NOTION_API_KEY` | required                                             |
| `NOTION_PAGE_ID` | `35fb438d-4d56-8151-8557-c5c1d6a66e03`               |
| `SCREENS_DIR`    | `../apps/ios/screens` (resolved relative to script)  |
