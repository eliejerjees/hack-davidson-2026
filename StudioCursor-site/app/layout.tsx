import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "StudioCursor — AI Editing Inside Your DAW",
  description:
    "Edit audio with natural language inside REAPER. Voice or text commands. Safe tool execution.",
  openGraph: {
    title: "StudioCursor",
    description: "Edit audio with natural language inside your DAW.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="scroll-smooth">
      <body className="bg-daw-bg text-daw-text antialiased">{children}</body>
    </html>
  );
}
