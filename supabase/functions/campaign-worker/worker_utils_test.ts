import {
  boundedInteger,
  forEachWithConcurrency,
  substitute,
} from "./worker_utils.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("worker configuration is bounded", () => {
  assert(boundedInteger(undefined, 100, 100) === 100, "fallback");
  assert(boundedInteger("500", 100, 100) === 100, "maximum");
  assert(boundedInteger("0", 100, 100) === 100, "minimum");
});

Deno.test("limited concurrency processes every recipient exactly once", async () => {
  const seen = new Map<number, number>();
  await forEachWithConcurrency([1, 2, 3, 4, 5, 6], 3, async (item) => {
    await Promise.resolve();
    seen.set(item, (seen.get(item) ?? 0) + 1);
  });
  assert(seen.size === 6, "all recipients processed");
  assert(
    [...seen.values()].every((count) => count === 1),
    "no duplicate processing",
  );
});

Deno.test("template substitution preserves structure", () => {
  const result = substitute({ body: "Olá {{nome}}", values: ["{{aula}}"] }, {
    nome: "Maria",
    aula: 3,
  }) as { body: string; values: string[] };
  assert(result.body === "Olá Maria", "name substitution");
  assert(result.values[0] === "3", "nested substitution");
});
