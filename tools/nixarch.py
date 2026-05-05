#!/usr/bin/env python3
import os
import re
from collections import defaultdict, Counter
from graphviz import Digraph

ROOT = os.path.abspath(os.path.expanduser("~/nixos"))

# -----------------------------
# Helpers
# -----------------------------
def rel(path: str) -> str:
    path = os.path.abspath(path)
    if path.startswith(ROOT + os.sep) or path == ROOT:
        return os.path.relpath(path, ROOT)
    return path

def is_inside_root(path: str) -> bool:
    path = os.path.abspath(path)
    return path.startswith(ROOT + os.sep) or path == ROOT

def norm_join(base_file: str, maybe_rel: str) -> str:
    """Resolve ./foo.nix relative to base_file directory."""
    base_dir = os.path.dirname(os.path.abspath(base_file))
    return os.path.normpath(os.path.join(base_dir, maybe_rel))

def classify(node: str) -> str:
    # node is already relative or "external:..."
    if node.startswith("external:"):
        return "external"
    if node == "flake.nix":
        return "flake"
    if node.startswith("hosts/"):
        return "hosts"
    if node.startswith("modules/"):
        return "modules"
    if node.startswith("profiles/"):
        return "profiles"
    if node == "home.nix" or node.startswith("home/"):
        return "home"
    if node.startswith("pkgs/"):
        return "pkgs"
    if node.startswith("tools/"):
        return "tools"
    return "misc"

CLUSTER_STYLE = {
    "flake":   {"label": "flake",    "color": "#c9c9c9"},
    "hosts":   {"label": "hosts",    "color": "#9ccfd8"},
    "modules": {"label": "modules",  "color": "#a6e3a1"},
    "profiles":{"label": "profiles", "color": "#f9e2af"},
    "home":    {"label": "home",     "color": "#fab387"},
    "pkgs":    {"label": "pkgs",     "color": "#cba6f7"},
    "tools":   {"label": "tools",    "color": "#94e2d5"},
    "external":{"label": "external", "color": "#f38ba8"},
    "misc":    {"label": "misc",     "color": "#b4befe"},
}

def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()

# -----------------------------
# Parse .nix import edges
# -----------------------------
RE_IMPORTS_BLOCK = re.compile(r'imports\s*=\s*\[(?P<body>.*?)\];', re.DOTALL)
RE_PATH_TOKEN = re.compile(r'(?P<q>"?)(?P<p>\./[^"\s\]]+?\.nix)(?P=q)')
RE_DIRECT_IMPORT = re.compile(r'\bimport\s+(?P<p>\./[^"\s]+?\.nix)\b')
RE_CALLPACKAGE = re.compile(r'\bcallPackage\s+(?P<p>\./[^"\s]+?)(?:\s|$)')

def extract_edges_from_nix(file_path: str):
    """Return list of (src, dst, kind). dst is relative path under ROOT if possible."""
    src = rel(file_path)
    text = read_text(file_path)
    edges = []

    # imports = [ ... ];
    for m in RE_IMPORTS_BLOCK.finditer(text):
        body = m.group("body")
        for pm in RE_PATH_TOKEN.finditer(body):
            target = norm_join(file_path, pm.group("p"))
            if is_inside_root(target):
                edges.append((src, rel(target), "imports"))
            else:
                edges.append((src, f"external:{pm.group('p')}", "imports"))

    # import ./x.nix
    for m in RE_DIRECT_IMPORT.finditer(text):
        target = norm_join(file_path, m.group("p"))
        if is_inside_root(target):
            edges.append((src, rel(target), "import"))
        else:
            edges.append((src, f"external:{m.group('p')}", "import"))

    # callPackage ./x (maybe without .nix)
    for m in RE_CALLPACKAGE.finditer(text):
        p = m.group("p")
        # common patterns: ./pkgs/foo { } or ./pkgs/foo/default.nix
        candidate = p
        if candidate.endswith("/"):
            candidate = candidate[:-1]
        # If it looks like a directory, assume default.nix
        # Heuristic: no extension AND exists as dir
        abs_candidate = norm_join(file_path, candidate)
        if not os.path.splitext(candidate)[1]:
            if os.path.isdir(abs_candidate):
                abs_candidate = os.path.join(abs_candidate, "default.nix")
            elif os.path.isfile(abs_candidate + ".nix"):
                abs_candidate = abs_candidate + ".nix"
        if is_inside_root(abs_candidate) and os.path.exists(abs_candidate):
            edges.append((src, rel(abs_candidate), "callPackage"))
        else:
            edges.append((src, f"external:{p}", "callPackage"))

    return edges

# -----------------------------
# Parse flake.nix module lists
# -----------------------------
def parse_flake_modules(flake_path: str):
    """
    Extract nixosConfigurations.<name>.modules = [ ... ];
    We capture tokens in the list:
      - ./relative/path.nix
      - identifiers like hyprland.nixosModules.default
      - home-manager.nixosModules.home-manager
      - overlayModule / allowUnfreeModule / commonHM (treated as external-ish but local symbols)
    """
    text = read_text(flake_path)

    # Find each nixosConfigurations entry block
    # This is a heuristic parser; it's "good enough" for a typical flake layout like yours.
    cfg_re = re.compile(
        r'nixosConfigurations\s*=\s*\{(?P<body>.*?)\};\s*\}\s*$',
        re.DOTALL | re.MULTILINE
    )
    m = cfg_re.search(text)
    if not m:
        return []

    body = m.group("body")

    # each config: name = nixpkgs.lib.nixosSystem { ... modules = [ ... ]; ... };
    entry_re = re.compile(
        r'(?P<name>[A-Za-z0-9_\-]+)\s*=\s*nixpkgs\.lib\.nixosSystem\s*\{\s*(?P<blk>.*?)\n\s*\};',
        re.DOTALL
    )

    modules_re = re.compile(r'\bmodules\s*=\s*\[(?P<mods>.*?)\];', re.DOTALL)

    edges = []
    for em in entry_re.finditer(body):
        name = em.group("name")
        blk = em.group("blk")
        mm = modules_re.search(blk)
        if not mm:
            continue
        mods = mm.group("mods")

        src = f"flake.nix::{name}"

        # tokenization: capture ./foo, identifiers with dots, and bare identifiers
        token_re = re.compile(r'(\./[^\s\]]+|[A-Za-z_][A-Za-z0-9_\-]*(?:\.[A-Za-z0-9_\-]+)*)')
        for tm in token_re.finditer(mods):
            tok = tm.group(1).strip()
            if tok.startswith("./"):
                abs_target = os.path.normpath(os.path.join(os.path.dirname(flake_path), tok))
                if is_inside_root(abs_target) and os.path.exists(abs_target):
                    edges.append((src, rel(abs_target), "flake-mod"))
                else:
                    edges.append((src, f"external:{tok}", "flake-mod"))
            else:
                # local symbol or external module ref
                # We keep it as external unless it's an obvious local symbol you want separate.
                edges.append((src, f"external:{tok}", "flake-mod"))
    return edges

# -----------------------------
# Build graph
# -----------------------------
def main():
    nodes = set()
    edges = []

    # Collect nix file edges
    for root, _, files in os.walk(ROOT):
        for f in files:
            if not f.endswith(".nix"):
                continue
            fp = os.path.join(root, f)
            nodes.add(rel(fp))
            edges.extend(extract_edges_from_nix(fp))

    # Add flake edges
    flake_path = os.path.join(ROOT, "flake.nix")
    if os.path.exists(flake_path):
        nodes.add("flake.nix")
        flake_edges = parse_flake_modules(flake_path)
        edges.extend(flake_edges)
        # include synthetic flake nodes
        for s, d, _ in flake_edges:
            nodes.add(s)
            nodes.add(d)
    else:
        print("WARN: flake.nix not found")

    # Ensure all edge endpoints are nodes
    for s, d, _ in edges:
        nodes.add(s); nodes.add(d)

    # Degree stats
    indeg = Counter()
    outdeg = Counter()
    for s, d, _ in edges:
        outdeg[s] += 1
        indeg[d] += 1

    # Build clustered DOT
    g = Digraph("nixos_arch", format="svg")
    g.attr(
        rankdir="LR",
        splines="ortho",
        concentrate="true",
        fontname="JetBrains Mono",
        fontsize="10",
        labelloc="t",
        label="NixOS Flake Architecture (imports / callPackage / flake modules)",
    )
    g.attr("node", shape="box", style="rounded,filled", fontname="JetBrains Mono", fontsize="9")
    g.attr("edge", arrowsize="0.6")

    # Create clusters
    cluster_graphs = {}
    for cname, style in CLUSTER_STYLE.items():
        sg = Digraph(name=f"cluster_{cname}")
        sg.attr(label=style["label"], color=style["color"], fontname="JetBrains Mono", fontsize="11")
        sg.attr(style="rounded")
        cluster_graphs[cname] = sg

    def add_node(n: str):
        cname = classify(n)
        fill = CLUSTER_STYLE.get(cname, CLUSTER_STYLE["misc"])["color"]
        # Shorten very long labels but keep uniqueness in node name.
        label = n
        cluster_graphs[cname].node(n, label=label, fillcolor=fill)

    for n in sorted(nodes):
        add_node(n)

    # Attach clusters
    for sg in cluster_graphs.values():
        g.subgraph(sg)

    # Edge styling by kind
    edge_style = {
        "imports":     {"style": "solid"},
        "import":      {"style": "solid"},
        "callPackage": {"style": "dashed"},
        "flake-mod":   {"style": "bold"},
    }

    for s, d, k in edges:
        st = edge_style.get(k, {"style": "solid"})
        g.edge(s, d, label=k if k == "flake-mod" else "", **st)

    # Output
    dot_path = os.path.join(ROOT, "nixos-arch.dot")
    svg_path = os.path.join(ROOT, "nixos-arch.svg")
    report_path = os.path.join(ROOT, "nixos-arch.report.txt")

    g.save(dot_path)
    g.render(filename=os.path.join(ROOT, "nixos-arch"), cleanup=False)  # creates .svg via format

    # Report
    def top10(counter):
        return counter.most_common(10)

    with open(report_path, "w", encoding="utf-8") as f:
        f.write("NixOS Arch Graph Report\n")
        f.write("=======================\n\n")
        f.write(f"Root: {ROOT}\n")
        f.write(f"Nodes: {len(nodes)}\n")
        f.write(f"Edges: {len(edges)}\n\n")

        f.write("Top 10 by incoming edges (most depended-on):\n")
        for n, c in top10(indeg):
            f.write(f"  {c:>4}  {n}\n")

        f.write("\nTop 10 by outgoing edges (biggest importers):\n")
        for n, c in top10(outdeg):
            f.write(f"  {c:>4}  {n}\n")

    print("Wrote:")
    print(f"  {dot_path}")
    print(f"  {svg_path}")
    print(f"  {report_path}")

if __name__ == "__main__":
    main()
