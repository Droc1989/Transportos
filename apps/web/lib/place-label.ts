/** Eticheta unei localități: „Satu Nou, Timiș” (fără județ, doar numele). Folosită pe server și în browser. */
export function placeLabel(p: { name: string; admin_name: string | null }): string {
  return p.admin_name ? `${p.name}, ${p.admin_name}` : p.name;
}
