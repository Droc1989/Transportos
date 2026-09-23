/** O eroare de buget nu permite apelul extern (fail closed). */
export async function addressBudget(consume: () => Promise<{ data: unknown; error: unknown }>): Promise<'allowed' | 'limited' | 'unavailable'> {
  try {
    const { data, error } = await consume();
    if (error || typeof data !== 'boolean') return 'unavailable';
    return data ? 'allowed' : 'limited';
  } catch { return 'unavailable'; }
}
