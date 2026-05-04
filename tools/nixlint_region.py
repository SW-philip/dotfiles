#!/usr/bin/env python3
import os
import re
from collections import defaultdict, Counter

ROOT = os.path.abspath(os.path.expanduser("~/nixos"))
MAX_DEPTH = 3

RE_IMPORTS_BLOCK = re.compile(r'imports\s*=\s*\[(?P<body>.*?)\];', re.DOTALL)
RE_PATH_TOKEN = re.compile(r'(?P<q>"?)(?P<p>\./[^"\s\]]+?\.nix)(?P=q)')
RE_DIRECT_IMPORT = re.compile(r'\bimport\s+(?P<p>\./[^"\s]+?\.nix)\b')
RE_CALLPACKAGE = re.compile(r'\bcallPackage\s+(?P<p>\./[^"\s]+?)(?:\s|$)')


def depth_from_root(path):
    rel = os.path.relpath(path, ROOT)
    if rel == ".":
        return 0
    return len(rel.split(os.sep)) - 1


def resolve(base_file, rel_path):
    return os.path.normpath(os.path.join(os.path.dirname(base_file), rel_path))


def extract_imports(file_path):
    with open(file_path, "r", encoding="utf-8") as f:
        text = f.read()

    found = set()

    for m in RE_IMPORTS_BLOCK.finditer(text):
        for pm in RE_PATH_TOKEN.finditer(m.group("body")):
            found.add(pm.group("p"))

    for m in RE_DIRECT_IMPORT.finditer(text):
        found.add(m.group("p"))

    for m in RE_CALLPACKAGE.finditer(text):
        found.add(m.group("p"))

    return found


def main():
    files = []
    for root, _, fs in os.walk(ROOT):
        for f in fs:
            if f.endswith(".nix"):
                path = os.path.join(root, f)
                if depth_from_root(path) <= MAX_DEPTH:
                    files.append(path)

    files = set(files)
    graph = defaultdict(set)

    for f in files:
        imports = extract_imports(f)
        for imp in imports:
            abs_path = resolve(f, imp)

            if abs_path in files:
                graph[f].add(abs_path)

    # Metrics
    indeg = Counter()
    outdeg = Counter()

    for src, targets in graph.items():
        outdeg[src] += len(targets)
        for t in targets:
            indeg[t] += 1

    print(f"\nRegion depth ≤ {MAX_DEPTH}")
    print(f"Files analyzed: {len(files)}")
    print(f"Edges within region: {sum(len(v) for v in graph.values())}")

    print("\nTop depended-on files:")
    for f, c in indeg.most_common(5):
        print(f"  {os.path.relpath(f, ROOT)} ({c})")

    print("\nTop importers:")
    for f, c in outdeg.most_common(5):
        print(f"  {os.path.relpath(f, ROOT)} ({c})")

    isolated = [f for f in files if f not in graph and indeg[f] == 0]
    if isolated:
        print("\nIsolated files:")
        for f in isolated:
            print(f"  {os.path.relpath(f, ROOT)}")


if __name__ == "__main__":
    main()
