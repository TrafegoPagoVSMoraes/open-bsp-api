import type { OutgoingInteractiveData } from "../_shared/types/message_types.ts";
import type { OutgoingInteractive } from "../_shared/types/whatsapp_endpoint_types.ts";

export function validateOutgoingInteractive(
  data: OutgoingInteractiveData,
): void {
  if (!data || typeof data !== "object") {
    throw new Error("Interactive data must be an object");
  }
  const d = data as Record<string, unknown>;

  if (d.type !== "button") {
    throw new Error("Interactive type must be 'button'");
  }

  if (
    !d.body || typeof d.body !== "object" || !("text" in d.body) ||
    typeof d.body.text !== "string" || d.body.text.trim() === ""
  ) {
    throw new Error(
      "Interactive body.text is required and must be a non-empty string",
    );
  }

  if (d.footer !== undefined) {
    if (
      typeof d.footer !== "object" || d.footer === null ||
      !("text" in d.footer) || typeof d.footer.text !== "string"
    ) {
      throw new Error("Interactive footer must have a text string");
    }
  }

  if (!d.action || typeof d.action !== "object" || d.action === null) {
    throw new Error("Interactive action must be an object");
  }
  const action = d.action as Record<string, unknown>;

  if (!("buttons" in action) || !Array.isArray(action.buttons)) {
    throw new Error("Interactive action.buttons must be an array");
  }

  const buttons = action.buttons as unknown[];
  if (buttons.length === 0) {
    throw new Error("Interactive must have at least 1 button");
  }
  if (buttons.length > 3) {
    throw new Error("Interactive must have at most 3 buttons");
  }

  const seenIds = new Set<string>();
  for (const btn of buttons) {
    if (!btn || typeof btn !== "object" || btn === null) {
      throw new Error("Each button must be an object");
    }
    const button = btn as Record<string, unknown>;
    if (button.type !== "reply") {
      throw new Error("Each button must be type 'reply'");
    }
    if (
      !button.reply || typeof button.reply !== "object" || button.reply === null
    ) {
      throw new Error("Each button must have a reply object");
    }
    const reply = button.reply as Record<string, unknown>;
    if (typeof reply.id !== "string" || reply.id.trim() === "") {
      throw new Error("Button reply.id must be a non-empty string");
    }
    if (typeof reply.title !== "string" || reply.title.trim() === "") {
      throw new Error("Button reply.title must be a non-empty string");
    }
    if (seenIds.has(reply.id)) {
      throw new Error("Button reply.id must be unique");
    }
    seenIds.add(reply.id);
  }
}

export function buildOutgoingInteractiveEndpointMessage(
  data: OutgoingInteractiveData,
): OutgoingInteractive {
  validateOutgoingInteractive(data);

  return {
    type: "interactive",
    interactive: data,
  };
}
