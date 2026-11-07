// Version strings. No herdr imports, so it loads under plain Node for tests.

/** Compares two versions part by part, numerically; parts split on `.` and
 *  `-`, a missing part counts as 0. Returns -1, 0 or 1. */
export function cmpVersion(a, b) {
  const x = a.split(/[.-]/).map(Number), y = b.split(/[.-]/).map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d) return Math.sign(d);
  }
  return 0;
}
