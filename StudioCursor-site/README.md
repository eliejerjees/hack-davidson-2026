# StudioCursor — Landing Site

Minimal, polished one-page landing site for **StudioCursor**, an AI-powered audio editing assistant that lives inside REAPER.

Built with **Next.js 15 (App Router)** + **TailwindCSS** — ready for Vercel deployment.

---

## Local development

```bash
# Install dependencies
npm install

# Start dev server
npm run dev
```

Then open [http://localhost:3000](http://localhost:3000).

---

## Deploy to Vercel

```bash
# Option 1 — Vercel CLI
npx vercel

# Option 2 — Push to GitHub and import at vercel.com/new
```

No environment variables required.

---

## Customising content

All editable text, links, and video config lives at the top of `app/page.tsx` in the `SITE` constant:

```ts
const SITE = {
  name: "StudioCursor",
  tagline: "Edit audio with natural language inside your DAW.",
  supporting: "Docked REAPER panel. Voice or text commands. Safe tool execution.",
  description: "...",
  links: {
    github: "https://github.com/your-repo",
    devpost: "https://devpost.com/your-submission",
  },
  video: {
    youtubeId: "your-youtube-id",  // leave empty to use local /demo.mp4
    src: "/demo.mp4",
  },
  pills: ["REAPER Panel", "Gemini Tool Calls", "STT / TTS"],
  footer: "Built for Hack@Davidson 2026",
};
```

### Swapping in a real video

**YouTube:** Set `youtubeId` to your video ID (e.g. `"dQw4w9WgXcQ"`).

**Local file:** Drop `demo.mp4` into the `public/` folder — it will be served from `/demo.mp4` automatically. Leave `youtubeId` empty.

---

## File structure

```
/
├── app/
│   ├── layout.tsx      # Root layout + metadata
│   ├── page.tsx        # Full one-page site (all sections)
│   └── globals.css     # Tailwind directives + DAW custom styles
├── public/             # Static assets (drop demo.mp4 here)
├── package.json
├── tailwind.config.ts
├── postcss.config.mjs
└── README.md
```

---

## Theme

Inspired by REAPER / Cakewalk DAW UI:

| Token | Value | Usage |
|---|---|---|
| `daw-bg` | `#111214` | Page background |
| `daw-panel` | `#18191d` | Card / panel surfaces |
| `daw-border` | `#2a2c32` | Panel borders |
| `daw-green` | `#4ade80` | Meter green, CTA, accents |
| `daw-amber` | `#fbbf24` | Peak indicator |
| `daw-red` | `#ef4444` | Record button, clip indicator |
| `daw-blue` | `#60a5fa` | Selected / active states |
