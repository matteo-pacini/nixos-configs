// Reports model, effort, context usage and (where known) prompt-cache expiry
// for the herdr sidebar through herdr-agent-report, after each assistant
// message in a root session. Subagent sessions are skipped: they would
// overwrite the pane's row with their own model and context.
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

// Cache lifetimes by upstream model prefix. OpenRouter does not say which
// lifetime its upstream gives, so only prefixes with a documented default
// are listed; anything else shows no cache timer.
const CACHE_TTL_SECONDS = [["anthropic/", 300]];

export const HerdrRowsPlugin = async ({ client, $ }) => {
  if (process.env.HERDR_ENV !== "1" || !process.env.HERDR_PANE_ID) {
    return {};
  }

  const childSessions = new Set();
  const contextLimits = new Map();
  let lastReport = "";

  async function contextLimit(providerID, modelID) {
    const key = `${providerID}/${modelID}`;
    if (!contextLimits.has(key)) {
      const { data } = await client.config.providers();
      const provider = data?.providers?.find((p) => p.id === providerID);
      contextLimits.set(key, provider?.models?.[modelID]?.limit?.context ?? 0);
    }
    return contextLimits.get(key);
  }

  // opencode stores the effort picked per model here; older messages don't
  // carry it themselves.
  async function storedVariant(providerID, modelID) {
    try {
      const state = JSON.parse(
        await readFile(join(homedir(), ".local/state/opencode/model.json"), "utf8"),
      );
      return state?.variant?.[`${providerID}/${modelID}`] ?? "";
    } catch {
      return "";
    }
  }

  return {
    event: async ({ event }) => {
      const info = event?.properties?.info;
      if (event?.type === "session.created" || event?.type === "session.updated") {
        if (info?.parentID) childSessions.add(info.id);
        return;
      }
      if (event?.type !== "message.updated" || info?.role !== "assistant") return;
      if (childSessions.has(info.sessionID)) return;

      const t = info.tokens ?? {};
      const used =
        t.total ||
        (t.input ?? 0) + (t.output ?? 0) + (t.reasoning ?? 0) + (t.cache?.read ?? 0) + (t.cache?.write ?? 0);
      // Streaming updates arrive with zero usage until the step finishes.
      if (!used) return;

      const effort = info.variant ?? (await storedVariant(info.providerID, info.modelID));
      const limit = await contextLimit(info.providerID, info.modelID).catch(() => 0);
      const args = [
        "--agent", "opencode",
        "--model", info.modelID.replace(/^.*\//, ""),
        "--effort", effort,
        "--ktokens", String(Math.floor(used / 1000)),
      ];
      if (limit) args.push("--pct", String(Math.floor((used * 100) / limit)));

      const ttl = CACHE_TTL_SECONDS.find(([prefix]) => info.modelID.startsWith(prefix))?.[1];
      const sentAt = Math.floor((info.time?.completed ?? info.time?.created ?? Date.now()) / 1000);
      if (ttl) args.push("--cache-until", String(sentAt + ttl), "--cache-mode", "clock");

      const report = args.join("\u001f");
      if (report === lastReport) return;
      lastReport = report;
      await $`herdr-agent-report ${args}`.quiet().nothrow();
    },
  };
};
