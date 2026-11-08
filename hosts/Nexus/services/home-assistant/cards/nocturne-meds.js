// nocturne-meds: one medicine's last month as a calendar, with its streak.
//
//   type: custom:nocturne-meds
//   name: Eutirox 75 µg
//   entity: sensor.meds_eutirox_taken_today   # above 0 while today's dose is logged
//   logged: input_datetime.meds_matteo_eutirox # optional: the time it was taken
//   when: morning                             # optional: shown while not yet taken
//   icon: mdi:pill                            # optional
//   days: 30                                  # optional: the window counted
//
// Past days come from the entity's long-term statistics, which the recorder
// never purges, so the entity needs a state_class. A day counts as taken when
// its daily mean is above TAKEN_MEAN, not when its max is: the sensor drops
// to 0 at midnight, but the 00:00 hour still records the 1 it had a moment
// before, so the max marks the day after every dose as taken too. Today comes
// from the live state.
//
// The streak is the run of taken days ending today, or ending yesterday while
// today's dose is not logged yet, so it only breaks after a whole day with
// no dose. It is worked out from the same days the calendar draws.
//
// Design system: https://claude.ai/artifact/LE95HYdwkCBnrbFUE9pvKY
// Redesign: https://claude.ai/artifact/CeCqB9X7gFgtZ8aG7Erm9U

const DAY_MS = 864e5;
// The daily mean of a 0/1 sensor is the fraction of the day it was 1. A dose
// logged later than about 23:58 stays under this and is not counted; the
// moment of 1 left over at midnight is far below it.
const TAKEN_MEAN = 0.001;
const RETRY_MS = 60e3;
// How far back the streak is followed; a longer one shows as this many days.
const STREAK_DAYS = 365;

const CSS = `
  :host {
    display: block;
    --m-raised: var(--input-fill-color, var(--secondary-background-color));
    --m-muted: var(--secondary-text-color);
    --m-ease: cubic-bezier(.2, .8, .2, 1);
  }
  ha-card { padding: 16px; display: flex; flex-direction: column; gap: 14px; }
  .head { display: flex; align-items: center; gap: 12px; }
  .badge { width: 40px; height: 40px; flex: none; border-radius: 14px; display: grid; place-items: center; color: var(--c); background: color-mix(in srgb, var(--c) 16%, transparent); }
  .badge ha-icon { --mdc-icon-size: 22px; }
  .text { flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; }
  .name { font-size: 14px; line-height: 20px; font-weight: 600; }
  .sub { font-size: 12px; line-height: 16px; color: var(--m-muted); }
  .sub.due { color: var(--orange-color); }
  .streak { display: flex; flex-direction: column; align-items: flex-end; text-align: right; }
  .streak .row { display: flex; align-items: baseline; gap: 6px; }
  .num { font-family: var(--ha-font-family-code, monospace); font-variant-numeric: tabular-nums; font-size: 30px; line-height: 32px; font-weight: 500; color: var(--m-muted); }
  .num.live { color: var(--green-color); }
  .num.risk { color: var(--orange-color); }
  .unit, .best { font-size: 12px; line-height: 16px; color: var(--m-muted); }
  .grid { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); row-gap: 6px; }
  .dow { font-size: 11px; line-height: 14px; font-weight: 600; letter-spacing: .08em; text-transform: uppercase; color: var(--m-muted); text-align: center; padding-bottom: 2px; }
  .cell { height: 34px; margin: 0 3px; border-radius: 10px; display: flex; align-items: center; justify-content: center; gap: 2px; background: var(--m-raised); color: var(--m-muted); font-family: var(--ha-font-family-code, monospace); font-variant-numeric: tabular-nums; font-size: 12px; font-weight: 500; transition: background 280ms var(--m-ease), color 280ms var(--m-ease); }
  .cell .mon { font-family: var(--ha-font-family-body, inherit); font-size: 9px; font-weight: 600; letter-spacing: .06em; text-transform: uppercase; }
  .cell.t { background: var(--green-color); color: var(--text-primary-color); }
  .cell.t.jl { margin-left: 0; border-top-left-radius: 0; border-bottom-left-radius: 0; }
  .cell.t.jr { margin-right: 0; border-top-right-radius: 0; border-bottom-right-radius: 0; }
  .cell.today:not(.t) { background: none; color: var(--primary-text-color); box-shadow: inset 0 0 0 2px var(--primary-color); }
  .cell.today.t { outline: 2px solid var(--primary-color); outline-offset: 2px; }
  .cell.out { opacity: .4; }
  .cell.future { visibility: hidden; }
  .foot { display: flex; align-items: center; gap: 12px; }
  .bar { flex: 1 1 auto; height: 6px; border-radius: 999px; background: var(--m-raised); overflow: hidden; }
  .bar div { height: 100%; border-radius: 999px; background: var(--green-color); transition: width 700ms var(--m-ease); }
  .count { font-family: var(--ha-font-family-code, monospace); font-variant-numeric: tabular-nums; font-size: 12px; }
  .foot .of { font-size: 12px; color: var(--m-muted); }
  @media (prefers-reduced-motion: reduce) { .cell, .bar div { transition: none; } }
`;

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

// Days are "YYYY-MM-DD" keys in Home Assistant's time zone, the zone its
// daily statistics are bucketed in. Arithmetic on them goes through UTC
// midnight, where every day is 24 hours long.
const utc = (key) => Date.UTC(+key.slice(0, 4), +key.slice(5, 7) - 1, +key.slice(8, 10));
const addDays = (key, n) => new Date(utc(key) + n * DAY_MS).toISOString().slice(0, 10);
const weekday = (key) => (new Date(utc(key)).getUTCDay() + 6) % 7; // Monday is 0

class NocturneMeds extends HTMLElement {
  setConfig(config) {
    if (!config.entity) throw new Error("nocturne-meds: `entity` is required");
    this._config = { days: 30, icon: "mdi:pill", ...config };
    this._taken = null;
    this._fetchedFor = null;
    this._seen = null;
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
    if (this._hass) this.hass = this._hass;
    else this._render();
  }

  set hass(hass) {
    this._hass = hass;
    const today = this._key(Date.now());
    if (this._fetchedFor !== today) {
      this._fetchedFor = today;
      this._fetch(today);
    }
    // hass is set on every state change in the house; redraw only for ours.
    const seen = [this._config.entity, this._config.logged, today].map((id) => hass.states[id] || id);
    if (this._seen && seen.every((s, i) => s === this._seen[i])) return;
    this._seen = seen;
    this._render();
  }

  getCardSize() {
    return 6;
  }

  getGridOptions() {
    return { columns: 12, min_columns: 6 };
  }

  _key(ms) {
    const tz = this._hass.config.time_zone;
    if (this._tz !== tz) {
      this._tz = tz;
      this._fmt = new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" });
    }
    return this._fmt.format(ms);
  }

  // The first day drawn: the Monday on or before the first day of the window.
  _gridStart(today) {
    const first = addDays(today, 1 - this._config.days);
    return addDays(first, -weekday(first));
  }

  // The first day fetched: far enough back for the grid and the streak.
  _firstDay(today) {
    const back = addDays(today, -STREAK_DAYS);
    const start = this._gridStart(today);
    return back < start ? back : start;
  }

  async _fetch(today) {
    const id = this._config.entity;
    try {
      const res = await this._hass.connection.sendMessagePromise({
        type: "recorder/statistics_during_period",
        // A day early, so the first local day is whole in any time zone.
        start_time: new Date(utc(this._firstDay(today)) - DAY_MS).toISOString(),
        statistic_ids: [id],
        period: "day",
        types: ["mean"],
        units: {},
      });
      this._taken = new Set((res[id] || []).filter((s) => s.mean > TAKEN_MEAN).map((s) => this._key(s.start)));
    } catch (err) {
      console.warn("[nocturne-meds]", id, err);
      setTimeout(() => {
        if (this._fetchedFor === today) this._fetchedFor = null;
      }, RETRY_MS);
    }
    this._render();
  }

  _render() {
    if (!this.shadowRoot || !this._config) return;
    const c = this._config;
    const hass = this._hass;
    const st = hass?.states[c.entity];
    const name = c.name || st?.attributes.friendly_name || c.entity;
    if (!hass || !st) {
      this.shadowRoot.innerHTML = `<style>${CSS}</style><ha-card><div class="name">${esc(name)}</div><div class="sub">${hass ? `${esc(c.entity)} not found` : ""}</div></ha-card>`;
      return;
    }

    const lang = hass.locale?.language || hass.language;
    const today = this._key(Date.now());
    const windowStart = addDays(today, 1 - c.days);
    const start = this._gridStart(today);
    const end = addDays(today, 6 - weekday(today));
    const takenToday = Number(st.state) > 0;
    const loaded = this._taken !== null;
    const taken = (k) => (k === today ? takenToday : loaded && this._taken.has(k));

    const keys = [];
    for (let k = start; k <= end; k = addDays(k, 1)) keys.push(k);

    let streak = 0;
    for (let k = takenToday ? today : addDays(today, -1); k >= this._firstDay(today) && taken(k); k = addDays(k, -1)) streak++;
    let best = 0;
    let run = 0;
    let count = 0;
    for (let k = windowStart; k <= today; k = addDays(k, 1)) {
      run = taken(k) ? run + 1 : 0;
      best = Math.max(best, run);
      if (taken(k)) count++;
    }

    const day = (k, opts) => new Date(utc(k)).toLocaleDateString(lang, { timeZone: "UTC", ...opts });
    const dows = [0, 1, 2, 3, 4, 5, 6].map((i) => `<div class="dow">${esc(day(addDays("2024-01-01", i), { weekday: "short" }))}</div>`).join("");
    const cells = keys.map((k, i) => {
      const t = taken(k);
      const col = weekday(k);
      const cls = ["cell"];
      if (k > today) cls.push("future");
      else {
        if (t) cls.push("t");
        if (t && col > 0 && taken(addDays(k, -1))) cls.push("jl");
        if (t && col < 6 && k < today && taken(addDays(k, 1))) cls.push("jr");
        if (k === today) cls.push("today");
        if (k < windowStart) cls.push("out");
      }
      const state = k === today && !t ? "not yet" : t ? "taken" : loaded ? "missed" : "loading";
      const mon = i === 0 || k.endsWith("-01") ? `<span class="mon">${esc(day(k, { month: "short" }))}</span>` : "";
      return `<div class="${cls.join(" ")}" title="${esc(day(k, { weekday: "short", day: "numeric", month: "short" }))}: ${state}"><span>${+k.slice(8)}</span>${mon}</div>`;
    }).join("");

    let sub = "Taken today";
    const ts = Number(hass.states[c.logged]?.attributes.timestamp);
    if (takenToday && ts && this._key(ts * 1000) === today) {
      sub += ` at ${new Date(ts * 1000).toLocaleTimeString(lang, { timeZone: this._tz, hour: "2-digit", minute: "2-digit", hour12: hass.locale?.time_format === "12" })}`;
    }
    if (!takenToday) sub = c.when ? `Not yet today · ${c.when}` : "Not yet today";
    const hue = takenToday ? "var(--green-color)" : "var(--orange-color)";
    const numCls = !loaded ? "" : takenToday && streak ? "live" : streak ? "risk" : "";

    this.shadowRoot.innerHTML = `<style>${CSS}</style>
      <ha-card>
        <div class="head">
          <div class="badge" style="--c: ${hue}"><ha-icon icon="${esc(c.icon)}"></ha-icon></div>
          <div class="text">
            <span class="name">${esc(name)}</span>
            <span class="sub${takenToday ? "" : " due"}">${esc(sub)}</span>
          </div>
          <div class="streak">
            <div class="row"><span class="num ${numCls}">${loaded ? streak : "–"}</span><span class="unit">day streak</span></div>
            <span class="best">${loaded ? `Best ${best} in ${c.days}` : ""}</span>
          </div>
        </div>
        <div class="grid" role="img" aria-label="${esc(`${name}: taken on ${count} of the last ${c.days} days, ${streak} day streak`)}">${dows}${cells}</div>
        <div class="foot">
          <div class="bar"><div style="width: ${loaded ? Math.round((count / c.days) * 100) : 0}%"></div></div>
          <span class="count">${loaded ? count : "–"}</span><span class="of">of the last ${c.days} days</span>
        </div>
      </ha-card>`;
  }
}

customElements.define("nocturne-meds", NocturneMeds);
window.customCards = window.customCards || [];
window.customCards.push({
  type: "nocturne-meds",
  name: "Nocturne meds",
  description: "A medicine's last month as a calendar, with its streak.",
});
