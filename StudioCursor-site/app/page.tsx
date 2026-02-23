"use client";

import { useRef } from "react";
import clsx from "clsx";

// ─── Site constants — edit these ──────────────────────────────────────────────
const SITE = {
  name: "StudioCursor",
  tagline: "Edit audio with natural language inside your DAW.",
  supporting:
    "Docked REAPER panel. Voice or text commands. Safe tool execution.",
  description:
    "StudioCursor is an AI-powered editing assistant built directly inside REAPER. Type or speak commands like \"fade out 2s\" or \"crossfade these clips\", and the system safely converts them into validated DAW actions. Multi-step commands work, and every run executes inside a single Undo block for safety.",
  links: {
    github: "https://github.com/eliejerjees/StudioCursor",
    devpost: "https://devpost.com/software/studiocursor?_gl=1*12azt62*_gcl_au*MTIwNDUxMTczNS4xNzcwNzk1ODIz*_ga*OTQ4MTEzODE0LjE3NzA3OTU4MjQ.*_ga_0YHJK3Y10M*czE3NzE4MzAxODQkbzgkZzEkdDE3NzE4MzAyNTQkajU5JGwwJGgw",
  },
  video: {
    youtubeId: "Lkqhr0Jfu08",
    src: "/demo.mp4",
  },
  pills: ["REAPER Panel", "Gemini Tool Calls", "STT / TTS"],
  footer: "Built for Hack@Davidson 2026",
};
// ──────────────────────────────────────────────────────────────────────────────

/* ── Tiny SVG icons ──────────────────────────────────────────────────────── */
function IconPlay() {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor">
      <polygon points="2,1 11,6 2,11" />
    </svg>
  );
}

function IconStop() {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor">
      <rect x="2" y="2" width="8" height="8" rx="1" />
    </svg>
  );
}

function IconRecord() {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor">
      <circle cx="6" cy="6" r="4" />
    </svg>
  );
}

function IconGitHub() {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z" />
    </svg>
  );
}

function IconExternal() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6" />
      <polyline points="15 3 21 3 21 9" />
      <line x1="10" y1="14" x2="21" y2="3" />
    </svg>
  );
}

/* ── Full-width hero waveform ─────────────────────────────────────────────── */
function HeroWaveform() {
  const BARS = 110;
  const VW = BARS * 11;
  const VH = 120;

  const heights = Array.from({ length: BARS }, (_, i) => {
    const t = i / BARS;
    const env = Math.pow(Math.sin(t * Math.PI), 0.32) * 0.88 + 0.12;
    const h = Math.abs(
      Math.sin(i * 0.43 + 0.5)  * 0.38 +
      Math.sin(i * 1.21 + 1.2)  * 0.28 +
      Math.sin(i * 2.87 + 0.8)  * 0.22 +
      Math.sin(i * 5.3  + 2.1)  * 0.12
    );
    return Math.max(0.05, h * env);
  });

  const maxH = Math.max(...heights);

  return (
    <div className="relative w-full h-48 pointer-events-none overflow-hidden">
      <svg
        viewBox={`0 0 ${VW} ${VH}`}
        preserveAspectRatio="none"
        className="absolute inset-0 w-full h-full"
      >
        {heights.map((h, i) => {
          const barH = Math.round((h / maxH) * (VH * 0.94) * 1000) / 1000;
          const mirrorH = Math.round(barH * 0.28 * 1000) / 1000;
          const x = i * 11 + 1;
          const y = Math.round((VH - barH) * 1000) / 1000;
          return (
            <g key={i}>
              {/* Main bar rising from bottom */}
              <rect
                x={x} y={y} width={9} height={barH}
                fill="#38bdf8" fillOpacity={0.22} rx={1.5}
              />
              {/* Dimmer mirror below the baseline for depth */}
              <rect
                x={x} y={VH} width={9} height={mirrorH}
                fill="#38bdf8" fillOpacity={0.08} rx={1.5}
                transform={`scale(1,-1) translate(0,${-VH * 2})`}
              />
            </g>
          );
        })}
        {/* Baseline */}
        <line
          x1="0" y1={VH} x2={VW} y2={VH}
          stroke="#38bdf8" strokeOpacity={0.15} strokeWidth={0.6}
        />
      </svg>
    </div>
  );
}

/* ── Transport Header ─────────────────────────────────────────────────────── */
function TransportHeader() {
  return (
    <header className="fixed top-0 left-0 right-0 z-50 h-10 bg-daw-panel border-b border-daw-border flex items-center px-4 gap-4">
      {/* Transport controls */}
      <div className="flex items-center gap-1">
        <button
          className="transport-btn w-7 h-7 rounded flex items-center justify-center text-daw-textMuted"
          aria-label="Play"
          title="Play"
        >
          <IconPlay />
        </button>
        <button
          className="transport-btn w-7 h-7 rounded flex items-center justify-center text-daw-textMuted"
          aria-label="Stop"
          title="Stop"
        >
          <IconStop />
        </button>
        <button
          className="transport-btn w-7 h-7 rounded flex items-center justify-center text-red-500"
          aria-label="Record"
          title="Record"
        >
          <IconRecord />
        </button>
      </div>

      {/* Divider */}
      <div className="w-px h-5 bg-daw-border" />

      {/* Brand */}
      <span className="font-mono text-xs font-semibold text-daw-text tracking-widest uppercase">
        {SITE.name}
      </span>

      {/* Spacer */}
      <div className="flex-1" />

      {/* Status pills */}
      <div className="flex items-center gap-2">
        {SITE.pills.map((pill) => (
          <span
            key={pill}
            className="hidden sm:inline-flex items-center px-2 py-0.5 rounded text-[10px] font-mono font-medium bg-daw-surface border border-daw-border text-daw-textDim tracking-wide"
          >
            {pill}
          </span>
        ))}
        {/* Online indicator */}
        <span className="flex items-center gap-1 text-[10px] font-mono text-daw-green">
          <span className="w-1.5 h-1.5 rounded-full bg-daw-green inline-block animate-pulse" />
          LIVE
        </span>
      </div>
    </header>
  );
}

/* ── Hero Section ─────────────────────────────────────────────────────────── */
function HeroSection({
  videoRef,
  linksRef,
}: {
  videoRef: React.RefObject<HTMLElement | null>;
  linksRef: React.RefObject<HTMLElement | null>;
}) {
  function scrollTo(ref: React.RefObject<HTMLElement | null>) {
    ref.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  return (
    <section className="relative h-[calc(100vh-2.5rem)] flex flex-col overflow-hidden">
      {/* Grid background */}
      <div
        className="absolute inset-0 bg-grid-daw"
        style={{ backgroundSize: "32px 32px" }}
      />

      {/* Mixer strip background gradient bars */}
      <div className="absolute inset-0 flex pointer-events-none overflow-hidden">
        {Array.from({ length: 16 }).map((_, i) => (
          <div
            key={i}
            className="flex-1 border-r border-daw-border/30"
            style={{
              background:
                i % 2 === 0
                  ? "rgba(30,32,38,0.4)"
                  : "rgba(24,25,29,0.4)",
            }}
          />
        ))}
      </div>

      {/* Main content — flex-1 so it fills space above the waveform */}
      <div className="relative z-10 flex-1 flex items-center justify-center px-6 pt-10">
        <div className="text-center max-w-3xl mx-auto">
          {/* Badge */}
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full border border-daw-border bg-daw-surface text-daw-textDim text-xs font-mono mb-8 tracking-wide">
            <span className="w-1.5 h-1.5 rounded-full bg-daw-green" />
            AI-Powered DAW Assistant
          </div>

          {/* Title */}
          <h1 className="text-5xl sm:text-6xl md:text-7xl font-bold tracking-tight text-daw-text mb-4">
            Studio
            <span className="text-daw-green">Cursor</span>
          </h1>

          {/* Tagline */}
          <p className="text-lg sm:text-xl text-daw-textDim mb-3 font-light">
            {SITE.tagline}
          </p>

          {/* Supporting */}
          <p className="text-sm text-daw-textMuted font-mono mb-10 tracking-wide">
            {SITE.supporting}
          </p>

          {/* CTAs */}
          <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
            <button
              onClick={() => scrollTo(videoRef)}
              className="btn-glow w-full sm:w-auto px-6 py-3 rounded bg-daw-green text-daw-bg font-semibold text-sm tracking-wide transition-all duration-200 hover:bg-[#7dd3fc] active:scale-95"
            >
              Watch Demo
            </button>
            <button
              onClick={() => scrollTo(linksRef)}
              className="btn-blue-glow w-full sm:w-auto px-6 py-3 rounded bg-daw-surface border border-daw-border text-daw-text font-semibold text-sm tracking-wide transition-all duration-200 hover:border-daw-borderBright hover:bg-daw-surfaceHover active:scale-95"
            >
              View Links
            </button>
          </div>
        </div>
      </div>

      {/* Waveform — flows naturally at the bottom, part of the same section */}
      <div className="relative w-full flex-none z-10">
        <HeroWaveform />
        {/* Scroll hint inside the waveform row */}
        <div className="absolute inset-x-0 bottom-4 flex flex-col items-center gap-1.5 text-daw-textMuted z-20 animate-bounce pointer-events-none">
          <span className="text-[10px] font-mono tracking-widest uppercase">scroll</span>
          <svg width="14" height="8" viewBox="0 0 14 8" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="1 1 7 7 13 1" />
          </svg>
        </div>
      </div>
    </section>
  );
}

/* ── Video Section ────────────────────────────────────────────────────────── */
function VideoSection({ sectionRef }: { sectionRef: React.RefObject<HTMLElement | null> }) {
  const hasYoutube = SITE.video.youtubeId && SITE.video.youtubeId.length > 0;

  return (
    <section
      ref={sectionRef as React.RefObject<HTMLElement>}
      id="demo"
      className="py-24 px-6"
    >
      <div className="max-w-4xl mx-auto">
        {/* Section label */}
        <div className="flex items-center gap-3 mb-8">
          <div className="h-px flex-1 bg-daw-border" />
          <span className="text-xs font-mono text-daw-textMuted tracking-widest uppercase">
            Preview Window
          </span>
          <div className="h-px flex-1 bg-daw-border" />
        </div>

        {/* Video panel */}
        <div className="panel-glow rounded-lg border border-daw-border bg-daw-panel overflow-hidden transition-all duration-200">
          {/* Panel title bar */}
          <div className="flex items-center gap-2 px-4 py-2 border-b border-daw-border bg-daw-surface">
            <div className="flex gap-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-daw-red opacity-70" />
              <span className="w-2.5 h-2.5 rounded-full bg-daw-amber opacity-70" />
              <span className="w-2.5 h-2.5 rounded-full bg-daw-green opacity-70" />
            </div>
            <span className="text-xs font-mono text-daw-textMuted ml-2">
              StudioCursor — Demo.mp4
            </span>
          </div>

          {/* Video embed */}
          <div className="relative w-full" style={{ paddingBottom: "56.25%" }}>
            {hasYoutube ? (
              <iframe
                className="absolute inset-0 w-full h-full"
                src="https://www.youtube.com/embed/Lkqhr0Jfu08"
                title="StudioCursor Demo"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowFullScreen
              />
            ) : (
              <video
                className="absolute inset-0 w-full h-full object-cover"
                src="/demo.mp4"
                controls
                poster=""
              >
                Your browser does not support HTML5 video.
              </video>
            )}
          </div>
        </div>

        {/* Caption */}
        <p className="text-center text-sm text-daw-textMuted font-mono mt-4 tracking-wide">
          Demo: natural language edits inside REAPER
        </p>
      </div>
    </section>
  );
}

/* ── Description Section ──────────────────────────────────────────────────── */
function DescriptionSection() {
  return (
    <section className="py-16 px-6">
      <div className="max-w-3xl mx-auto">
        {/* Section label */}
        <div className="flex items-center gap-3 mb-8">
          <div className="h-px flex-1 bg-daw-border" />
          <span className="text-xs font-mono text-daw-textMuted tracking-widest uppercase">
            What It Is
          </span>
          <div className="h-px flex-1 bg-daw-border" />
        </div>

        {/* Panel card */}
        <div className="panel-glow rounded-lg border border-daw-border bg-daw-panel p-8 transition-all duration-200">
          {/* Decorative meter strip inside the card */}
          <div className="flex items-end gap-[3px] h-8 mb-6 opacity-50">
            {Array.from({ length: 36 }).map((_, i) => {
              const height = Math.round(30 + Math.sin(i * 0.7) * 40 + Math.cos(i * 1.3) * 20);
              const color =
                height > 80
                  ? "bg-daw-red"
                  : height > 60
                  ? "bg-daw-amber"
                  : "bg-daw-meter";
              return (
                <div
                  key={i}
                  className={clsx("w-[3px] flex-none rounded-sm", color)}
                  style={{ height: `${Math.max(20, height)}%` }}
                />
              );
            })}
          </div>

          <p className="text-daw-textDim leading-relaxed text-base sm:text-lg">
            {SITE.description}
          </p>

          {/* Feature chips */}
          <div className="flex flex-wrap gap-2 mt-6">
            {[
              "Natural Language Commands",
              "Voice + Text Input",
              "Single Undo Block",
              "Validated Tool Execution",
              "Multi-Step Pipelines",
            ].map((tag) => (
              <span
                key={tag}
                className="px-3 py-1 rounded-full text-xs font-mono border border-daw-border bg-daw-surface text-daw-textDim tracking-wide"
              >
                {tag}
              </span>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

/* ── Links Section ────────────────────────────────────────────────────────── */
function LinksSection({ sectionRef }: { sectionRef: React.RefObject<HTMLElement | null> }) {
  return (
    <section
      ref={sectionRef as React.RefObject<HTMLElement>}
      id="links"
      className="py-16 px-6"
    >
      <div className="max-w-3xl mx-auto">
        {/* Section label */}
        <div className="flex items-center gap-3 mb-8">
          <div className="h-px flex-1 bg-daw-border" />
          <span className="text-xs font-mono text-daw-textMuted tracking-widest uppercase">
            Links
          </span>
          <div className="h-px flex-1 bg-daw-border" />
        </div>

        <div className="grid sm:grid-cols-2 gap-4">
          {/* GitHub */}
          <a
            href="https://github.com/eliejerjees/StudioCursor"
            target="_blank"
            rel="noopener noreferrer"
            className="group panel-glow flex items-center gap-4 p-6 rounded-lg border border-daw-border bg-daw-panel transition-all duration-200 hover:border-daw-borderBright hover:bg-daw-surfaceHover"
          >
            <span className="text-daw-textMuted group-hover:text-daw-text transition-colors duration-200">
              <IconGitHub />
            </span>
            <div>
              <div className="font-semibold text-daw-text text-sm group-hover:text-daw-green transition-colors duration-200">
                GitHub
              </div>
              <div className="text-xs text-daw-textMuted font-mono mt-0.5">
                Source code &amp; README
              </div>
            </div>
            <div className="ml-auto text-daw-textMuted group-hover:text-daw-textDim transition-colors duration-200">
              <IconExternal />
            </div>
          </a>

          {/* Devpost */}
          <a
            href="https://devpost.com/software/studiocursor?ref_content=my-projects-tab&ref_feature=my_projects"
            target="_blank"
            rel="noopener noreferrer"
            className="group panel-glow flex items-center gap-4 p-6 rounded-lg border border-daw-border bg-daw-panel transition-all duration-200 hover:border-daw-borderBright hover:bg-daw-surfaceHover"
          >
            <span className="text-daw-textMuted group-hover:text-daw-blue transition-colors duration-200">
              {/* Devpost "D" icon */}
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden="true"
              >
                <path d="M6.002 1.61L0 12.004 6.002 22.39h11.996L24 12.004 17.998 1.61zm1.593 16.526l-4.04-6.132 4.04-6.132H12c3.39 0 5.9 2.65 5.9 6.132C17.9 15.49 15.39 18.136 12 18.136z" />
              </svg>
            </span>
            <div>
              <div className="font-semibold text-daw-text text-sm group-hover:text-daw-blue transition-colors duration-200">
                Devpost
              </div>
              <div className="text-xs text-daw-textMuted font-mono mt-0.5">
                Hackathon submission
              </div>
            </div>
            <div className="ml-auto text-daw-textMuted group-hover:text-daw-textDim transition-colors duration-200">
              <IconExternal />
            </div>
          </a>
        </div>
      </div>
    </section>
  );
}

/* ── Footer ───────────────────────────────────────────────────────────────── */
function Footer() {
  return (
    <footer className="border-t border-daw-border bg-daw-panel py-8 px-6">
      <div className="max-w-3xl mx-auto">
        {/* Timeline ruler */}
        <div className="flex items-center gap-0 mb-6 overflow-hidden">
          {Array.from({ length: 48 }).map((_, i) => (
            <div key={i} className="flex flex-col items-center flex-1">
              <div
                className={clsx(
                  "bg-daw-border",
                  i % 4 === 0 ? "w-px h-3" : "w-px h-1.5"
                )}
              />
            </div>
          ))}
        </div>

        <div className="flex flex-col sm:flex-row items-center justify-between gap-2 text-xs font-mono text-daw-textMuted">
          <span>{SITE.name}</span>
          <span>{SITE.footer}</span>
        </div>
      </div>
    </footer>
  );
}

/* ── Page ─────────────────────────────────────────────────────────────────── */
export default function Home() {
  const videoRef = useRef<HTMLElement>(null);
  const linksRef = useRef<HTMLElement>(null);

  return (
    <main className="min-h-screen">
      <TransportHeader />

      {/* Push content below fixed header */}
      <div className="pt-10">
        <HeroSection videoRef={videoRef} linksRef={linksRef} />
        <VideoSection sectionRef={videoRef} />
        <DescriptionSection />
        <LinksSection sectionRef={linksRef} />
        <Footer />
      </div>
    </main>
  );
}
