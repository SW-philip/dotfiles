#!/usr/bin/env python3
import os
import re
from collections import defaultdict

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


def resolve(base, rel):
    return os.path.normpath(os.path.join(os.path.dirname(base), rel))


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


def build_graph():
    graph = defaultdict(set)

    for root, _, files in os.walk(ROOT):
        for f in files:
            if not f.endswith(".nix"):
                continue

            path = os.path.join(root, f)

            for imp in extract_imports(path):
                abs_path = resolve(path, imp)

                if abs_path.startswith(ROOT) and os.path.exists(abs_path):
                    graph[path].add(abs_path)

    return graph


def reverse_graph(graph):
    rev = defaultdict(set)
    for src, targets in graph.items():
        for t in targets:
            rev[t].add(src)
    return rev


def find_flake_entrypoints():
    flake = os.path.join(ROOT, "flake.nix")
    entry = set()

    if not os.path.exists(flake):
        return entry

    with open(flake, "r", encoding="utf-8") as f:
        text = f.read()

    matches = re.findall(r'\./hosts/[^\s\]]+', text)
    for m in matches:
        abs_path = os.path.normpath(os.path.join(ROOT, m))
        entry.add(abs_path)

    return entry


def trace_upwards(node, rev_graph, visited, chain, entrypoints):
    if node in visited:
        return

    visited.add(node)
    chain.append(node)

    parents = rev_graph.get(node, set())

    if not parents:
        print("  ← ".join(os.path.relpath(x, ROOT) for x in chain))
        return

    for p in parents:
        if p in entrypoints:
            print("  ← ".join(os.path.relpath(x, ROOT) for x in chain + [p]))
        else:
            trace_upwards(p, rev_graph, visited.copy(), chain.copy(), entrypoints)


def main():
    graph = build_graph()
    rev_graph = reverse_graph(graph)
    entrypoints = find_flake_entrypoints()

    shallow_files = [
        os.path.join(root, f)
        for root, _, files in os.walk(ROOT)
        for f in files
        if f.endswith(".nix")
        and depth_from_root(os.path.join(root, f)) <= MAX_DEPTH
    ]

    print(f"\nAnalyzing files ≤ depth {MAX_DEPTH}...\n")

    for file_path in shallow_files:
        print(f"\n{os.path.relpath(file_path, ROOT)}")
        if file_path not in rev_graph:
            print("  (No one imports this)")
        else:
            trace_upwards(file_path, rev_graph, set(), [], entrypoints)


if __name__ == "__main__":
    main()
