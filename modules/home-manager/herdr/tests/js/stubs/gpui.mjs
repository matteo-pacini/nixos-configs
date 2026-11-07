// Stand-in for herdr-app's "gpui-kit" and "gpui-base": loads, draws nothing.

export const svg = () => {
  throw new Error("gpui stub: drawing isn't tested");
};
export const image = svg;
