import {
  AssistantMessageComponent,
  ToolExecutionComponent,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import type { AssistantMessage } from "@earendil-works/pi-ai";

const THINKING_ROWS: ThinkingMode = "hide";

type ThinkingMode = "hide" | "live" | "pi";

type QuietToolsState = { thinking: ThinkingMode };

const STATE_KEY = Symbol.for("quiet-tools:state:v1");
const TOOL_ROWS_KEY = Symbol.for("quiet-tools:tool-rows:v1");
const THINKING_ROWS_KEY = Symbol.for("quiet-tools:thinking-rows:v1");

const globals = globalThis as typeof globalThis & Record<symbol, unknown>;

function isState(value: unknown): value is QuietToolsState {
  return typeof value === "object" && value !== null && "thinking" in value;
}

function quietToolsState(): QuietToolsState {
  const existing = globals[STATE_KEY];
  if (isState(existing)) {
    existing.thinking = THINKING_ROWS;
    return existing;
  }
  const created: QuietToolsState = { thinking: THINKING_ROWS };
  globals[STATE_KEY] = created;
  return created;
}

type ToolRow = {
  expanded: boolean;
  toolName: string;
  result?: { isError?: boolean };
  imageComponents: { render(width: number): string[] }[];
  imageSpacers: ({ render(width: number): string[] } | undefined)[];
  render(width: number): string[];
};

function installToolRows(): void {
  if (globals[TOOL_ROWS_KEY] === true) return;
  const prototype = ToolExecutionComponent.prototype as unknown as ToolRow;
  const render = prototype.render;

  prototype.render = function (width: number): string[] {
    if (this.expanded) return render.call(this, width);

    const lines: string[] = [];
    if (this.result?.isError) {
      lines.push(`✗ ${this.toolName} failed (ctrl+o to expand)`);
    }
    for (const [index, image] of this.imageComponents.entries()) {
      const spacer = this.imageSpacers[index];
      if (spacer) lines.push(...spacer.render(width));
      lines.push(...image.render(width));
    }
    return lines;
  };

  globals[TOOL_ROWS_KEY] = true;
}

function installThinkingRows(): void {
  if (globals[THINKING_ROWS_KEY] === true) return;
  const prototype = AssistantMessageComponent.prototype;
  const updateContent = prototype.updateContent;

  prototype.updateContent = function (
    message: AssistantMessage,
    isStreaming?: boolean,
  ): void {
    const mode = quietToolsState().thinking;
    const drop =
      mode === "hide" || (mode === "live" && isStreaming !== true);
    if (!drop) return updateContent.call(this, message, isStreaming);

    const content = message.content.filter((block) => block.type !== "thinking");
    if (content.length === message.content.length) {
      return updateContent.call(this, message, isStreaming);
    }
    return updateContent.call(this, { ...message, content }, isStreaming);
  };

  globals[THINKING_ROWS_KEY] = true;
}

export default function (_pi: ExtensionAPI): void {
  quietToolsState();
  installToolRows();
  installThinkingRows();
}
