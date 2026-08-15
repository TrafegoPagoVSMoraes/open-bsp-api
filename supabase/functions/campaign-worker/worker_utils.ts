export type JsonObject = Record<string, unknown>;

export function boundedInteger(
  value: string | undefined,
  fallback: number,
  maximum: number,
) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed >= 1
    ? Math.min(parsed, maximum)
    : fallback;
}

export function substitute(value: unknown, variables: JsonObject): unknown {
  if (typeof value === "string") {
    return value.replace(
      /\{\{([a-zA-Z0-9_.-]+)\}\}/gu,
      (_match, key: string) =>
        variables[key] === undefined || variables[key] === null
          ? ""
          : String(variables[key]),
    );
  }
  if (Array.isArray(value)) {
    return value.map((item) => substitute(item, variables));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as JsonObject).map(([key, item]) => [
        key,
        substitute(item, variables),
      ]),
    );
  }
  return value;
}

export async function forEachWithConcurrency<T>(
  items: T[],
  concurrency: number,
  processItem: (item: T) => Promise<void>,
) {
  let next = 0;
  await Promise.all(Array.from(
    { length: Math.min(Math.max(1, concurrency), items.length) },
    async () => {
      while (next < items.length) await processItem(items[next++]);
    },
  ));
}
