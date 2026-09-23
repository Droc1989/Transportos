/** Fără destinație explicită, pagina principală alege destinația după rol. */
export function loginDestination(next: string | null | undefined): string {
  if (!next || !next.startsWith('/') || next.startsWith('//') || /[\\\r\n]/.test(next)) return '/';
  return next;
}
