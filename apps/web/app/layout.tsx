import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import { getLocale } from '@/lib/i18n';
import './globals.css';

export const metadata: Metadata = {
  title: 'TransportOS',
  description: 'Rezervări, dispecerat și urmărire pentru transportul RO–AT–DE.',
};

export default async function RootLayout({ children }: { children: ReactNode }) {
  const locale = await getLocale();
  return (
    <html lang={locale}>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Overpass:wght@400;600;700;800;900&family=Overpass+Mono:wght@500;700&display=swap"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
