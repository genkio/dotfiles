import { isAbsolute, relative, resolve, sep } from "node:path";
import type { Usage } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  ExtensionContext,
  SessionEntry,
} from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

function formatContextWindow(tokens: number): string {
  if (tokens >= 1e6) return `${Number((tokens / 1e6).toFixed(1))}m`;
  return `${Math.round(tokens / 1e3)}k`;
}

function isDeepSeekPeak(timestamp: string): boolean {
  const date = new Date(timestamp);
  const day = date.getUTCDay();
  if (day === 0 || day === 6) return false;
  const hour = date.getUTCHours() + date.getUTCMinutes() / 60;
  return (hour >= 1 && hour < 4) || (hour >= 6 && hour < 10);
}

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

const BALANCE_REFRESH_MS = 60_000;
const BALANCE_TIMEOUT_MS = 5_000;
const BALANCE_URL = "https://api.deepseek.com/user/balance";

const isRecord = (value: unknown): value is { [key: string]: unknown } =>
  typeof value === "object" && value !== null;

function parseBalance(payload: unknown): string | undefined {
  if (!isRecord(payload) || !Array.isArray(payload["balance_infos"])) return undefined;
  const infos = payload["balance_infos"].filter(isRecord);
  const info = infos.find((entry) => entry["currency"] === "CNY") ?? infos[0];
  if (!info || typeof info["total_balance"] !== "string") return undefined;
  return `${info["currency"] === "CNY" ? "¥" : "$"}${info["total_balance"]}`;
}

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

      let balance: string | undefined;
      let fetching = false;
      let disposed = false;
      const refreshBalance = async (): Promise<void> => {
        if (fetching || ctx.model?.provider !== "deepseek") return;
        fetching = true;
        try {
          const apiKey = await ctx.modelRegistry.getApiKeyForProvider("deepseek");
          if (!apiKey) return;
          const response = await fetch(BALANCE_URL, {
            headers: { Authorization: `Bearer ${apiKey}` },
            signal: AbortSignal.timeout(BALANCE_TIMEOUT_MS),
          });
          if (!response.ok) return;
          const payload: unknown = await response.json();
          const next = parseBalance(payload);
          if (disposed || next === undefined || next === balance) return;
          balance = next;
          tui.requestRender();
        } catch {
        } finally {
          fetching = false;
        }
      };
      void refreshBalance();
      const timer = setInterval(() => void refreshBalance(), BALANCE_REFRESH_MS);

      return {
        dispose() {
          disposed = true;
          clearInterval(timer);
          unsubscribe();
        },
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
          const balanceText =
            balance && ctx.model?.provider === "deepseek" ? `/${balance}` : "";
          const costText = theme.fg("dim", `$${cost.toFixed(2)}${balanceText}`);

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
            contextColored,
            costText,
            theme.fg("dim", model),
            theme.fg("dim", cwd),
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
