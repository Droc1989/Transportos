export function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Lipsește variabila de mediu ${name}. Vezi apps/web/.env.example.`);
  }
  return value;
}
