'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

export type NavLabels = Record<
  'trips' | 'alerts' | 'requests' | 'newBooking' | 'newTrip' | 'routes' | 'vehicles' | 'drivers' | 'team' | 'export' | 'site',
  string
>;

export function Nav({ labels, alertCount, requestCount }: { labels: NavLabels; alertCount: number; requestCount: number }) {
  const path = usePathname();
  const items = [
    { href: '/dispecerat', label: labels.trips },
    { href: '/dispecerat/alerte', label: labels.alerts, badge: alertCount },
    { href: '/dispecerat/cereri', label: labels.requests, badge: requestCount },
    { href: '/dispecerat/rezervare-noua', label: labels.newBooking },
    { href: '/dispecerat/curse/noua', label: labels.newTrip },
    { href: '/dispecerat/rute', label: labels.routes },
    { href: '/dispecerat/vehicule', label: labels.vehicles },
    { href: '/dispecerat/soferi', label: labels.drivers },
    { href: '/dispecerat/site', label: labels.site },
    { href: '/dispecerat/echipa', label: labels.team },
    { href: '/dispecerat/export', label: labels.export },
  ];
  return (
    <nav aria-label="Dispecerat" style={{ display: 'contents' }}>
      {items.map((item) => (
        <Link key={item.href} href={item.href} aria-current={path === item.href ? 'page' : undefined}>
          {item.label}
          {'badge' in item && item.badge ? <span className="nav-badge">{item.badge}</span> : null}
        </Link>
      ))}
    </nav>
  );
}
