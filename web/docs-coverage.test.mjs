import test from "node:test";
import assert from "node:assert/strict";
import { checkCoverage } from "./docs-coverage.mjs";

const catalogue = [
  { slug: "bags", surfaces: ["Inventory grid", "Search field", "Saved searches"] },
  { slug: "chat", surfaces: ["Message history"] },
];
// What the built pages placed: the captions of their figures, and the capture ids.
const placed = {
  bags: { captions: ["Inventory grid", "Quick filters"], captures: ["bags-inventory", "bags-search"] },
  chat: { captions: ["Message history"], captures: ["chat-history"] },
};

test("every surface is a caption, inside a placed capture, or a gap with a reason", () => {
  const gaps = [
    { page: "bags", surface: "Search field", capture: "bags-search" },
    { page: "bags", surface: "Saved searches", gap: "No surface of its own." },
  ];
  assert.deepEqual(checkCoverage(catalogue, placed, gaps), { surfaces: 4, captioned: 2, inCapture: 1, gaps: 1 });
});

test("an uncovered surface fails and is named", () => {
  assert.throws(() => checkCoverage(catalogue, placed, [{ page: "bags", surface: "Search field", capture: "bags-search" }]),
    /bags: Saved searches is neither a caption nor listed/);
});

test("a gap entry for a surface that is already a caption is stale", () => {
  const gaps = [
    { page: "bags", surface: "Inventory grid", gap: "old reason" },
    { page: "bags", surface: "Search field", capture: "bags-search" },
    { page: "bags", surface: "Saved searches", gap: "No surface of its own." },
  ];
  assert.throws(() => checkCoverage(catalogue, placed, gaps), /bags: Inventory grid is a caption; remove its known-gaps entry/);
});

test("unknown pages, unknown surfaces, empty reasons and unplaced captures fail", () => {
  const base = [{ page: "bags", surface: "Search field", capture: "bags-search" }, { page: "bags", surface: "Saved searches", gap: "No surface of its own." }];
  assert.throws(() => checkCoverage(catalogue, placed, [...base, { page: "maps", surface: "Canvas", gap: "x" }]), /unknown page maps/);
  assert.throws(() => checkCoverage(catalogue, placed, [...base, { page: "bags", surface: "Keyring", gap: "x" }]), /bags: unknown surface Keyring/);
  assert.throws(() => checkCoverage(catalogue, placed, [base[0], { page: "bags", surface: "Saved searches", gap: " " }]), /Saved searches needs a reason or a capture/);
  assert.throws(() => checkCoverage(catalogue, placed, [{ page: "bags", surface: "Search field", capture: "bags-filters" }, base[1]]), /bags-filters is not placed on bags/);
  assert.throws(() => checkCoverage(catalogue, placed, [...base, base[1]]), /bags: Saved searches is listed twice/);
});
