import type { ReactNode } from 'react';

/**
 * Formatare simplă și sigură pentru textele firmelor (știri, „Despre noi”).
 * Suportă: paragrafe (rând gol între ele), „## Titlu”, liste cu „- ”, **îngroșat** și
 * [text](https://link). Nu interpretează HTML: totul e text, deci nu se poate injecta cod.
 */
export function RichText({ text }: { text: string | null | undefined }) {
  if (!text) return null;
  const blocks = text.replace(/\r\n/g, '\n').split(/\n{2,}/).map((b) => b.trim()).filter(Boolean);
  return (
    <>
      {blocks.map((block, i) => {
        if (block.startsWith('## ')) return <h2 key={i}>{inline(block.slice(3))}</h2>;
        const lines = block.split('\n');
        if (lines.every((l) => l.trim().startsWith('- '))) {
          return (
            <ul key={i}>
              {lines.map((l, j) => <li key={j}>{inline(l.trim().slice(2))}</li>)}
            </ul>
          );
        }
        return (
          <p key={i}>
            {lines.map((l, j) => (
              <span key={j}>
                {j > 0 && <br />}
                {inline(l)}
              </span>
            ))}
          </p>
        );
      })}
    </>
  );
}

const TOKEN = /(\*\*[^*]+\*\*|\[[^\]]+\]\(https?:\/\/[^)\s]+\))/g;

function inline(text: string): ReactNode[] {
  return text.split(TOKEN).filter(Boolean).map((part, i) => {
    if (part.startsWith('**') && part.endsWith('**')) return <strong key={i}>{part.slice(2, -2)}</strong>;
    const link = /^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/.exec(part);
    if (link) {
      return (
        <a key={i} href={link[2]} rel="nofollow noopener noreferrer" target="_blank">
          {link[1]}
        </a>
      );
    }
    return part;
  });
}

/** Rezumat în text simplu (fără marcaje), pentru descrieri și meta. */
export function plainText(text: string | null | undefined, max = 180): string {
  const clean = (text ?? '').replace(/\*\*|##\s|^-\s/gm, '').replace(/\[([^\]]+)\]\([^)]+\)/g, '$1').replace(/\s+/g, ' ').trim();
  return clean.length > max ? `${clean.slice(0, max - 1)}…` : clean;
}
