"""Render actual companion replay JSON; no game client or browser automation."""
import argparse
import json
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
import numpy as np


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def panel(ax, before, after):
    polys = [[(-p[0], -p[2]) for p in points] for _, points in after["polygons"]]
    corridor = set(after["corridor"])
    colors = ["#36575b" if key in corridor else "#202f3e" for key, _ in after["polygons"]]
    old, new = -np.array(before["samples"])[:, :2], -np.array(after["samples"])[:, :2]
    coarse = -np.array(after["coarse"])[:, [0, 2]]
    ax.set_facecolor("#111b28")
    ax.add_collection(PolyCollection(polys, facecolors=colors, edgecolors="#526372", linewidths=.3))
    ax.plot(*coarse.T, color="#ffc36b", linewidth=1, alpha=.7, label="Original center graph")
    ax.plot(*old.T, color="#fd8f83", linewidth=1.7, label="Original follower")
    ax.plot(*new.T, color="#5df6bf", linewidth=2, label="New corridor lookahead")
    ax.set_aspect("equal")
    ax.set_xlabel("East → (world yards)")
    ax.set_ylabel("← North / South → (world yards)")
    ax.grid(alpha=.06)
    return old, coarse


def overview(ax, before, after):
    old, coarse = panel(ax, before, after)
    ax.set_xlim(coarse[:, 0].min()-12, coarse[:, 0].max()+12)
    ax.set_ylim(coarse[:, 1].max()+12, coarse[:, 1].min()-12)
    ax.scatter(*old[0], color="white", s=35, zorder=5)
    ax.annotate("Start: " + ", ".join(f"{v*100:.1f}" for v in after.get("startMap", [.533, .465])), old[0], xytext=(8, -15), textcoords="offset points")
    marker = -np.array(after["marker"])
    ax.scatter(*marker, color="#ff78cb", marker="*", s=100, zorder=5)
    ax.annotate("Dawn marker", marker, xytext=(-90, 12), textcoords="offset points")
    ax.set_title(f"Actual deployed mesh · {len(after['corridor'])}-polygon corridor", color="#eaf2ff", pad=14)
    legend = ax.legend(loc="upper left", facecolor="#111b28", edgecolor="#526372")
    for text in legend.get_texts():
        text.set_color("#eaf2ff")


def detail(ax, before, after):
    panel(ax, before, after)
    raw = np.array(before["samples"])
    directions = raw[:, 2:] - raw[:, :2]
    directions /= np.linalg.norm(directions, axis=1)[:, None]
    index = int(np.argmin((directions[1:] * directions[:-1]).sum(axis=1))) + 1
    center = -raw[index, :2]
    ax.set_xlim(center[0]-11, center[0]+11)
    ax.set_ylim(center[1]+11, center[1]-11)
    for at in (index-1, index):
        origin, target = -raw[at, :2], -raw[at, 2:]
        vector = target-origin
        vector = vector / np.linalg.norm(vector)*3
        ax.arrow(*origin, *vector, color="#fff", width=.05, head_width=.6, length_includes_head=True, zorder=6)
    ax.set_title("Original sharpest turn · white arrows", color="#eaf2ff", pad=14)


def render(before, after, output):
    plt.rcParams.update({"font.family": "DejaVu Sans", "text.color": "#eaf2ff",
                        "axes.labelcolor": "#c4d5e6", "xtick.color": "#9bb1c5",
                        "ytick.color": "#9bb1c5", "axes.edgecolor": "#60768b"})
    fig, axes = plt.subplots(1, 2, figsize=(16, 8), facecolor="#111b28")
    overview(axes[0], before, after)
    detail(axes[1], before, after)
    fig.suptitle("RikUI navigation: before / after movement replay", fontsize=20, y=.98)
    fig.text(.05, .055,
             f"Same mesh and A* corridor. Backward turns: {before['reversals']} → {after['reversals']}. "
             f"Near-waypoint hides: {before['hidden']} → {after['hidden']}. Both reach the modeled approach.",
             fontsize=12)
    fig.text(.05, .025, "Rounded screenshot start; archived quest marker. Simulated movement only — native collision and final interaction remain unverified.",
             fontsize=10, color="#aebdce")
    fig.subplots_adjust(left=.06, right=.98, top=.88, bottom=.16, wspace=.20)
    fig.savefig(output, dpi=160, facecolor=fig.get_facecolor())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("output")
    args = parser.parse_args()
    before, after = load(args.before), load(args.after)
    assert before["polygons"] == after["polygons"], "Mesh changed between replays"
    assert before["corridor"] == after["corridor"], "Search corridor changed"
    assert before["complete"] and after["complete"], "Comparison requires complete movement"
    output = Path(args.output)
    if output.exists():
        raise FileExistsError(output)
    render(before, after, output)
    print(output)


if __name__ == "__main__":
    main()
