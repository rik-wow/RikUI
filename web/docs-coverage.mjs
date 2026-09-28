// Every catalogued surface must be shown: as the caption of a capture on its guide, inside another
// capture placed on that guide, or as a documented gap. `placed` maps a page slug to the captions and
// capture ids its built guide placed; `gaps` is tools/site-renders/known-gaps.json.
export function checkCoverage(catalogue, placed, gaps) {
  const problems = [];
  const pages = new Map(catalogue.map(page => [page.slug, page]));
  const listed = new Map();
  for (const entry of gaps) {
    const page = pages.get(entry.page);
    if (!page) { problems.push("known-gaps: unknown page " + entry.page); continue; }
    if (!page.surfaces.includes(entry.surface)) { problems.push(entry.page + ": unknown surface " + entry.surface); continue; }
    const key = entry.page + "\u0000" + entry.surface;
    if (listed.has(key)) { problems.push(entry.page + ": " + entry.surface + " is listed twice"); continue; }
    const hasCapture = typeof entry.capture === "string" && entry.capture !== "";
    const hasGap = typeof entry.gap === "string" && entry.gap.trim() !== "";
    if (hasCapture === hasGap) { problems.push(entry.page + ": " + entry.surface + " needs a reason or a capture, not both or neither"); continue; }
    if (hasCapture && !(placed[entry.page]?.captures || []).includes(entry.capture))
      problems.push(entry.page + ": " + entry.capture + " is not placed on " + entry.page);
    listed.set(key, entry);
  }
  const counts = { surfaces: 0, captioned: 0, inCapture: 0, gaps: 0 };
  for (const page of catalogue) {
    const captions = new Set(placed[page.slug]?.captions || []);
    for (const surface of page.surfaces) {
      counts.surfaces++;
      const entry = listed.get(page.slug + "\u0000" + surface);
      if (captions.has(surface)) {
        counts.captioned++;
        if (entry) problems.push(page.slug + ": " + surface + " is a caption; remove its known-gaps entry");
      } else if (!entry) problems.push(page.slug + ": " + surface + " is neither a caption nor listed in known-gaps.json");
      else if (entry.capture) counts.inCapture++;
      else counts.gaps++;
    }
  }
  if (problems.length) throw Error("Catalogue coverage:\n" + problems.join("\n"));
  return counts;
}
