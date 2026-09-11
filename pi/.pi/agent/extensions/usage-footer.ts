// Footer with only the numbers worth showing, in Claude Code's order:
//
//   (deepseek) deepseek-flash (max) · 6.7%/1m · ~/dotfiles (main) · $1.487
//
// The built-in footer splits this over two rows and also carries cumulative
// in/out tokens, cache read/write counters, the cache-hit rate, and pi's
// auto-compaction marker; those are dropped here. The rest of the pieces
// (model + thinking level, context usage, cwd + git branch + session name)
// keep the built-in footer's formats.
//
// The cost is recomputed instead of summing usage.cost.total, because pi prices
// every request at the model catalog's rates, and pi.dev's catalog lists
// DeepSeek's PEAK rates only. DeepSeek bills off-peak requests at half price
// (peak = Mon-Fri 01:00-04:00 and 06:00-10:00 UTC, everything else off-peak):
//   https://api-docs.deepseek.com/quick_start/pricing/
// So pi reports the worst case whenever a session runs outside those windows.
// Here deepseek entries are priced from their token counts and per-entry
// timestamps (off-peak counts half), and every other provider keeps pi's stored
// usage.cost.total. Rate lookup is model-specific, so sessions that switched
// between deepseek models stay correct.

import { isAbsolute, relative, resolve, sep } from "node:path";
import type { Usage } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  ExtensionContext,
  SessionEntry,
} from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

/** Context window in Claude's style: 1000000 -> "1m", 200000 -> "200k". */
function formatContextWindow(tokens: number): string {
  if (tokens >= 1e6) return `${Number((tokens / 1e6).toFixed(1))}m`;
  return `${Math.round(tokens / 1e3)}k`;
}

/** DeepSeek peak hours: Mon-Fri 01:00-04:00 and 06:00-10:00 UTC. */
function isDeepSeekPeak(timestamp: string): boolean {
  const date = new Date(timestamp);
  const day = date.getUTCDay();
  if (day === 0 || day === 6) return false;
  const hour = date.getUTCHours() + date.getUTCMinutes() / 60;
  return (hour >= 1 && hour < 4) || (hour >= 6 && hour < 10);
}

/** Usage recorded on an entry: assistant/tool messages, or a generated summary. */
function entryUsage(entry: SessionEntry): Usage | undefined {
  if (entry.type === "message") {
    if (entry.message.role === "assistant") return entry.message.usage;
    if (entry.message.role === "toolResult") return entry.message.usage;
    return undefined;
  }
  if (entry.type === "compaction" || entry.type === "branch_summary") {
    return entry.usage;
  }
  return undefined;
}

type Rates = { input: number; output: number; cacheRead: number; cacheWrite: number };

/**
 * Sum session cost, halving deepseek entries recorded off-peak. Rate lookups
 * are cached per model, and the result is cached per entry count: the session
 * tree is append-only, so a new entry (including model_change) invalidates it.
 */
function correctedCost(
  ctx: ExtensionContext,
  rateCache: Map<string, Rates | undefined>,
  cached: { count: number; total: number },
): number {
  const entries = ctx.sessionManager.getEntries();
  if (entries.length === cached.count) return cached.total;

  let total = 0;
  for (const entry of entries) {
    const usage = entryUsage(entry);
    if (!usage) continue;

    const assistant =
      entry.type === "message" && entry.message.role === "assistant"
        ? entry.message
        : undefined;
    // Summaries and tool results carry usage but no provider; attribute them
    // to the active provider rather than assuming a price.
    const provider = assistant?.provider ?? ctx.model?.provider;
    if (provider !== "deepseek") {
      total += usage.cost.total;
      continue;
    }

    let rates: Rates | undefined;
    if (assistant) {
      const key = `${provider}/${assistant.model}`;
      if (rateCache.has(key)) rates = rateCache.get(key);
      else {
        rates = ctx.modelRegistry.find(provider, assistant.model)?.cost;
        rateCache.set(key, rates);
      }
    }
    rates ??= ctx.model?.cost;
    if (!rates) {
      total += usage.cost.total;
      continue;
    }

    const peak = isDeepSeekPeak(entry.timestamp) ? 1 : 0.5;
    total +=
      (peak *
        (usage.input * rates.input +
          usage.output * rates.output +
          usage.cacheRead * rates.cacheRead +
          usage.cacheWrite * rates.cacheWrite)) /
      1e6;
  }

  cached.count = entries.length;
  cached.total = total;
  return total;
}

/** cwd with ~ instead of $HOME, matching the built-in footer. */
function formatCwd(cwd: string): string {
  const home = process.env.HOME ?? process.env.USERPROFILE;
  if (!home) return cwd;
  const rel = relative(resolve(home), resolve(cwd));
  if (rel === "" || (!rel.startsWith(`..${sep}`) && rel !== ".." && !isAbsolute(rel))) {
    return rel === "" ? "~" : `~${sep}${rel}`;
  }
  return cwd;
}

export default function (pi: ExtensionAPI): void {
  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;

    const rateCache = new Map<string, Rates | undefined>();
    const costCache = { count: -1, total: 0 };

    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsubscribe = footerData.onBranchChange(() => tui.requestRender());
      return {
        dispose: unsubscribe,
        invalidate() {},
        render(width: number): string[] {
          const usage = ctx.getContextUsage();
          const contextWindow = usage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
          const percent = usage?.percent ?? null;
          const contextText =
            percent === null
              ? `?/${formatContextWindow(contextWindow)}`
              : `${percent.toFixed(1)}%/${formatContextWindow(contextWindow)}`;
          const contextColored =
            percent !== null && percent > 90
              ? theme.fg("error", contextText)
              : percent !== null && percent > 70
                ? theme.fg("warning", contextText)
                : contextText;

          const cost = correctedCost(ctx, rateCache, costCache);
          const costText = theme.fg("dim", `$${cost.toFixed(3)}`);

          let model = ctx.model?.id ?? "no-model";
          if (ctx.model?.reasoning) {
            const level = ctx.thinkingLevel ?? "off";
            model = level === "off" ? `${model} (thinking off)` : `${model} (${level})`;
          }
          if (footerData.getAvailableProviderCount() > 1 && ctx.model) {
            model = `(${ctx.model.provider}) ${model}`;
          }

          let cwd = formatCwd(ctx.sessionManager.getCwd());
          const branch = footerData.getGitBranch();
          if (branch) cwd = `${cwd} (${branch})`;
          const sessionName = ctx.sessionManager.getSessionName();
          if (sessionName) cwd = `${cwd} • ${sessionName}`;

          const line = [
            theme.fg("dim", model),
            contextColored,
            theme.fg("dim", cwd),
            costText,
          ].join(" · ");
          const lines = [truncateToWidth(line, width, theme.fg("dim", "..."))];
          const statuses = footerData.getExtensionStatuses();
          if (statuses.size > 0) {
            const statusLine = Array.from(statuses.entries())
              .sort(([a], [b]) => a.localeCompare(b))
              .map(([, text]) => text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim())
              .join(" ");
            lines.push(truncateToWidth(statusLine, width, theme.fg("dim", "...")));
          }
          return lines;
        },
      };
    });
  });
}
