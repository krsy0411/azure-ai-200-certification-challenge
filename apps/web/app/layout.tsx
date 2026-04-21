import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'AI-200 Challenge',
  description: 'Enterprise RAG assistant — Azure AI-200 certification challenge',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}
