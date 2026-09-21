"""Plot the actual two-floor steering replay, without game or browser automation."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
import numpy as np


def draw_map(ax, records):
    lower = records[0]
    marker = -np.array(lower["marker"])
    polygons = [[(-p[0], -p[2]) for p in points] for _, points in lower["polygons"]]
    ax.add_collection(PolyCollection(polygons, facecolors="#eef1f5",
                                    edgecolors="#b1bdcb", linewidths=.35))
    for record, color, label in zip(records, ["#166fbd", "#d47715"], ["Lower floor", "Upper floor"]):
        points = -np.array(record["samples"])[:, :2]
        ax.plot(*points.T, color=color, linewidth=2, label=label)
    ax.scatter(*marker, marker="*", s=140, color="#ab2666", zorder=5, label="2D quest marker")
    ax.set_xlim(marker[0]-38, marker[0]+30)
    ax.set_ylim(marker[1]+40, marker[1]-22)
    ax.set_aspect("equal")
    ax.set_title("Building approach: actual model polygons")
    ax.set_xlabel("East (world yards)")
    ax.set_ylabel("South (world yards)")
    ax.legend(loc="upper left")


def draw_height(ax, records):
    for record, color, label in zip(records, ["#166fbd", "#d47715"], ["Lower floor", "Upper floor"]):
        points = np.array(record["samples"])[:, :2]
        heights = np.array(record["sampleHeights"])
        distance = np.r_[0, np.cumsum(np.linalg.norm(np.diff(points, axis=0), axis=1))]
        remaining = distance[-1]-distance
        keep = remaining <= 70
        ax.plot(-remaining[keep], heights[keep], color=color, linewidth=2,
                label=f"{label}: {record['targetModelHeight']:.2f} yd")
        ax.scatter(0, heights[-1], color=color, s=40)
    ax.set_title("Final 70 yards: replay stays on its selected floor")
    ax.set_xlabel("Distance before end of simulated walk (yards)")
    ax.set_ylabel("Modeled height (world yards)")
    ax.grid(alpha=.2)
    ax.legend()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lower")
    parser.add_argument("upper")
    parser.add_argument("output")
    args = parser.parse_args()
    records = [json.loads(Path(path).read_text(encoding="utf-8")) for path in (args.lower, args.upper)]
    assert records[0]["meshSourceSha256"] == records[1]["meshSourceSha256"]
    for index, record in enumerate(records, 1):
        assert record["complete"] and record["selectedModelFloor"] == index
        assert len(record["sampleHeights"]) == len(record["samples"])
    output = Path(args.output)
    if output.exists():
        raise FileExistsError(output)
    fig, axes = plt.subplots(1, 2, figsize=(14, 7))
    draw_map(axes[0], records)
    draw_height(axes[1], records)
    fig.suptitle("Bitter Rivals: routes to both modeled floors", fontsize=18)
    fig.text(.04, .04, "Exact archived marker and installed Forever 69913 mesh. Floor choices are explicit routing preferences.",
             fontsize=10)
    fig.text(.04, .015, "Automatic quest-target floor and native traversal remain unverified. These are simulated movement paths.",
             fontsize=10)
    fig.subplots_adjust(left=.07, right=.98, top=.89, bottom=.14, wspace=.25)
    fig.savefig(output, dpi=150)
    print(output)


if __name__ == "__main__":
    main()
