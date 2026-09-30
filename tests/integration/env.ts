// The runner passes its inputs to the extension host through environment
// variables; a missing one is a broken launch, not a value to default.

/** The value of environment variable `name`; throws when the launch did not set it. */
export function requireEnv(name: string): string {
  const value = process.env[name];
  if (value === undefined) throw new Error(`${name} is not set`);
  return value;
}
