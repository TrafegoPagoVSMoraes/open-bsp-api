import { deepEqual, ok, throws } from "node:assert/strict";

import {
  buildOutgoingInteractiveEndpointMessage,
  validateOutgoingInteractive,
} from "./interactive.ts";

// ============================================================
// validateOutgoingInteractive tests
// ============================================================

function makeButton(id: string, title: string) {
  return { type: "reply" as const, reply: { id, title } };
}

function makeData(buttons: ReturnType<typeof makeButton>[]) {
  return {
    type: "button" as const,
    body: { text: "Texto principal" },
    action: { buttons },
  };
}

Deno.test("validateOutgoingInteractive: 1 button valid", () => {
  const data = makeData([
    makeButton("consent:subscribe:v1", "Voltar a receber"),
  ]);
  validateOutgoingInteractive(data);
});

Deno.test("validateOutgoingInteractive: 3 buttons valid", () => {
  const data = makeData([
    makeButton("btn-1", "Sim"),
    makeButton("btn-2", "Nao"),
    makeButton("btn-3", "Talvez"),
  ]);
  validateOutgoingInteractive(data);
});

Deno.test("validateOutgoingInteractive: footer valid", () => {
  const data = {
    ...makeData([makeButton("btn-1", "Ok")]),
    footer: { text: "Rodape" },
  };
  validateOutgoingInteractive(data);
});

Deno.test("validateOutgoingInteractive: 0 buttons rejected", () => {
  const data = makeData([]);
  throws(
    () => validateOutgoingInteractive(data),
    /at least 1 button/,
  );
});

Deno.test("validateOutgoingInteractive: 4 buttons rejected", () => {
  const data = makeData([
    makeButton("b1", "1"),
    makeButton("b2", "2"),
    makeButton("b3", "3"),
    makeButton("b4", "4"),
  ]);
  throws(
    () => validateOutgoingInteractive(data),
    /at most 3 buttons/,
  );
});

Deno.test("validateOutgoingInteractive: empty body rejected", () => {
  const data = {
    type: "button" as const,
    body: { text: "  " },
    action: { buttons: [makeButton("b1", "1")] },
  };
  throws(
    () => validateOutgoingInteractive(data as never),
    /body\.text/,
  );
});

Deno.test("validateOutgoingInteractive: missing body rejected", () => {
  const data = {
    type: "button" as const,
    action: { buttons: [makeButton("b1", "1")] },
  };
  throws(
    () => validateOutgoingInteractive(data as never),
    /body\.text/,
  );
});

Deno.test("validateOutgoingInteractive: non-reply button type rejected", () => {
  const data = {
    type: "button" as const,
    body: { text: "x" },
    action: { buttons: [{ type: "cta_url", reply: { id: "b1", title: "1" } }] },
  };
  throws(
    () => validateOutgoingInteractive(data as never),
    /type 'reply'/,
  );
});

Deno.test("validateOutgoingInteractive: empty id rejected", () => {
  const data = makeData([makeButton("   ", "title")]);
  throws(
    () => validateOutgoingInteractive(data),
    /reply\.id/,
  );
});

Deno.test("validateOutgoingInteractive: empty title rejected", () => {
  const data = makeData([makeButton("b1", "")]);
  throws(
    () => validateOutgoingInteractive(data),
    /reply\.title/,
  );
});

Deno.test("validateOutgoingInteractive: duplicate ids rejected", () => {
  const data = makeData([
    makeButton("dup", "A"),
    makeButton("dup", "B"),
  ]);
  throws(
    () => validateOutgoingInteractive(data),
    /unique/,
  );
});

Deno.test("validateOutgoingInteractive: non-button type rejected", () => {
  const data = {
    type: "list" as const,
    body: { text: "x" },
    action: { buttons: [makeButton("b1", "1")] },
  };
  throws(
    () => validateOutgoingInteractive(data as never),
    /type must be 'button'/,
  );
});

Deno.test("validateOutgoingInteractive: not an object rejected", () => {
  throws(
    () => validateOutgoingInteractive(null as never),
    /must be an object/,
  );
  throws(
    () => validateOutgoingInteractive("x" as never),
    /must be an object/,
  );
});

Deno.test("validateOutgoingInteractive: footer without text rejected", () => {
  const data = {
    type: "button" as const,
    body: { text: "x" },
    footer: {},
    action: { buttons: [makeButton("b1", "1")] },
  };
  throws(
    () => validateOutgoingInteractive(data as never),
    /footer/,
  );
});

// ============================================================
// buildOutgoingInteractiveEndpointMessage: payload shape
// ============================================================

Deno.test(
  "buildOutgoingInteractiveEndpointMessage: payload has correct shape and no duplicate wrapper",
  () => {
    const data = {
      type: "button" as const,
      body: { text: "Texto principal" },
      footer: { text: "Texto opcional" },
      action: {
        buttons: [{
          type: "reply" as const,
          reply: { id: "consent:subscribe:v1", title: "Voltar a receber" },
        }],
      },
    };

    const result = buildOutgoingInteractiveEndpointMessage(data);

    // Check type and interactive structure
    ok(result.type === "interactive", "type must be 'interactive'");
    ok(
      result.interactive.type === "button",
      "interactive.type must be 'button'",
    );

    // Check body
    deepEqual(result.interactive.body, { text: "Texto principal" });

    // Check footer
    deepEqual(result.interactive.footer, { text: "Texto opcional" });

    // Check buttons
    deepEqual(result.interactive.action.buttons, [{
      type: "reply",
      reply: { id: "consent:subscribe:v1", title: "Voltar a receber" },
    }]);

    // Explicit no double-wrap assertion
    ok(
      !("interactive" in result.interactive),
      "Payload must NOT have interactive.interactive",
    );
    ok(
      !("data" in result.interactive),
      "Payload must NOT have interactive.data wrapper",
    );
  },
);

Deno.test(
  "buildOutgoingInteractiveEndpointMessage: invalid interactive throws",
  () => {
    const data = {
      type: "button" as const,
      body: { text: "x" },
      action: { buttons: [] }, // 0 buttons -> reject
    };

    throws(
      () => buildOutgoingInteractiveEndpointMessage(data),
      /at least 1 button/,
    );
  },
);
