// opencode plugin for hosts with the herdr-app agent-tree mod. Inside a
// herdr-app terminal, sets the labels Claude Code's statusLine sets (model,
// effort, context, version) from opencode's session events, for the mod to
// draw, and the session id for its restart button. opencode reports no
// prompt-cache expiry, so there is no cache label.
// Uses the opencode 2 plugin API (a default export with `id` and `setup`).

import { execFile } from "node:child_process";

const term = process.env.HC_TERMINAL_ID;

// An empty value removes the label.
const label = (values) =>
  execFile("hc", ["label", term, ...Object.entries(values).map(([k, v]) => `${k}=${v ?? ""}`)], () => {});

export default {
  id: "herdr.labels",
  async setup(ctx) {
    if (!term) return;
    // `${providerID}/${modelID}` -> { name, context }
    const models = new Map();
    const loadModels = async () => {
      const r = await ctx.model.list().catch(() => null);
      for (const m of r?.data ?? r ?? []) models.set(`${m.providerID}/${m.modelID ?? m.id}`, { name: m.name, context: m.limit?.context });
    };
    await loadModels();
    // Sub-agent sessions report to their parent's; only the session the pane
    // shows is labelled.
    const children = new Set();
    let model = null;

    label({ "agent.version": ctx.app?.version });
    const controller = new AbortController();
    void (async () => {
      for await (const event of ctx.event.subscribe({
        signal: controller.signal,
        types: ["session.created", "session.step.started", "session.step.ended"],
      })) {
        const d = event.data ?? {};
        if (event.type === "session.created" && d.parentID) children.add(d.sessionID);
        if (children.has(d.sessionID)) continue;
        if (event.type === "session.step.started" && d.model) {
          model = d.model;
          if (!models.has(`${model.providerID}/${model.id}`)) await loadModels();
          label({
            "opencode.session": d.sessionID,
            "agent.model": models.get(`${model.providerID}/${model.id}`)?.name ?? model.id,
            "agent.effort": model.variant,
          });
        }
        if (event.type === "session.step.ended" && d.tokens && model) {
          const t = d.tokens;
          const used = (t.input ?? 0) + (t.output ?? 0) + (t.reasoning ?? 0) + (t.cache?.read ?? 0) + (t.cache?.write ?? 0);
          const context = models.get(`${model.providerID}/${model.id}`)?.context;
          label({
            "opencode.session": d.sessionID,
            "agent.ctx": context ? Math.min(100, Math.round((used * 100) / context)) : "",
            "agent.ctxk": context ? Math.floor(used / 1000) : "",
          });
        }
      }
    })().catch(() => {});
    return () => controller.abort();
  },
};
