import Link from 'next/link';
import type { ReactNode } from 'react';
import { requirePlatformAdmin } from '@/lib/admin';
import { signOut } from '../login/actions';

export default async function AdminLayout({ children }: { children: ReactNode }) {
  await requirePlatformAdmin();
  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          TransportOS
          <div style={{ fontSize: 13, fontWeight: 800, color: 'var(--accent)' }}>Super Admin</div>
        </div>
        <Link href="/admin">Firme</Link>
        <Link href="/admin/aprobari">De aprobat</Link>
        <form action={signOut}>
          <button className="btn btn-ghost">Ieși din cont</button>
        </form>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}
