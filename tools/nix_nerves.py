#!/usr/bin/env python3
import os
import re
from collections import defaultdict, Counter, deque
from graphviz import Digraph

ROOT = os.path.abspath(os.path.expanduser("~/nixos"))

# -----------------------------
# Regexes (heuristic parser)
# -----------------------------
# capture ./foo.nix, ../foo.nix, ../../bar/default.nix, etc (quoted or not)
RE_REL_NIX_PATH = re.compile(r'(?P<q>"?)(?P<p>(?:\./|\.\./)[^"\s\]]+?\.nix)(?P=q)')
RE_IMPORTS_BLOCK = re.compile(r'imports\s*=\s*\[(?P<body>.*?)\];', re.DOTALL)
RE_DIRECT_IMPORT = re.compile(r'\bimport\s+(?P<p>(?:\./|\.\./)[^"\s]+?\.nix)\b')
RE_CALLPACKAGE = re.compile(r'\bcallPackage\s+(?P<p>(?:\./|\.\./)[^"\s\]]+)(?:\s|$)')
RE_FLAKE_NIXOSCONFIG = re.compile(
    r'(?P<name>[A-Za-z0-9_\-]+)\s*=\s*nixpkgs\.lib\.nixosSystem\s*\{\s*(?P<body>.*?)\n\s*\};',
    re.DOTALL
)
RE_FLAKE_MODULES_LIST = re.compile(r'\bmodules\s*=\s*\[(?P<body>.*?)\];', re.DOTALL)
RE_FLAKE_OVERLAY_CALLPKG = re.compile(r'\bcallPackage\s+(?P<p>(?:\./|\.\./)[^"\s\]]+)(?:\s|\{|\()')
RE_HM_USERS_IMPORT = re.compile(r'home-manager\.users\.[A-Za-z0-9_\-]+\s*=\s*import\s+(?P<p>(?:\./|\.\./)[^"\s]+?\.nix)\b')

# A loose token matcher for module lists: ./path, ../path, identifiers (hyprland.nixosModules.default)
RE_TOKEN = re.compile(r'(\.\.?/[^"\s\]]+|[A-Za-z_][A-Za-z0-9_\-]*(?:\.[A-Za-z0-9_\-]+)*)')

def is_inside_root(path: str) -> bool:
    p = os.path.abspath(path)
    return p == ROOT or p.startswith(ROOT + os.sep)

def rel(path: str) -> str:
    p = os.path.abspath(path)
    if is_inside_root(p):
        return os.path.relpath(p, ROOT)
    return p

def resolve(base_file: str, rpath: str) -> str:
    base_dir = os.path.dirname(os.path.abspath(base_file))
    return os.path.normpath(os.path.join(base_dir, rpath))

def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()

def norm_callpackage_target(base_file: str, p: str) -> str:
    """
    Resolve callPackage target:
      - if it's a dir => dir/default.nix
      - if it lacks .nix and <path>.nix exists => add .nix
      - otherwise keep as-is
    """
    abs_candidate = resolve(base_file, p)
    if os.path.isdir(abs_candidate):
        abs_candidate = os.path.join(abs_candidate, "default.nix")
    else:
        _, ext = os.path.splitext(abs_candidate)
        if ext == "":
            if os.path.exists(abs_candidate + ".nix"):
                abs_candidate = abs_candidate + ".nix"
    return abs_candidate

# -----------------------------
# Extract edges from a .nix file
# -----------------------------
def extract_edges_from_file(file_path: str):
    src = rel(file_path)
    text = read_text(file_path)
    edges = []

    # imports = [ ... ];
    for m in RE_IMPORTS_BLOCK.finditer(text):
        body = m.group("body")
        for pm in RE_REL_NIX_PATH.finditer(body):
            p = pm.group("p")
            tgt_abs = resolve(file_path, p)
            if is_inside_root(tgt_abs) and os.path.exists(tgt_abs):
                edges.append((src, rel(tgt_abs), "imports"))
            else:
                edges.append((src, f"external:{p}", "imports"))

    # import ../x.nix
    for m in RE_DIRECT_IMPORT.finditer(text):
        p = m.group("p")
        tgt_abs = resolve(file_path, p)
        if is_inside_root(tgt_abs) and os.path.exists(tgt_abs):
            edges.append((src, rel(tgt_abs), "import"))
        else:
            edges.append((src, f"external:{p}", "import"))

    # callPackage ../foo or ../foo/default.nix
    for m in RE_CALLPACKAGE.finditer(text):
        p = m.group("p")
        tgt_abs = norm_callpackage_target(file_path, p)
        if is_inside_root(tgt_abs) and os.path.exists(tgt_abs):
            edges.append((src, rel(tgt_abs), "callPackage"))
        else:
            edges.append((src, f"external:{p}", "callPackage"))

    return edges

# -----------------------------
# Extract edges from flake.nix wiring
# -----------------------------
def extract_edges_from_flake(flake_path: str):
    text = read_text(flake_path)
    edges = []
    nodes = set()

    # (1) nixosConfigurations.<name> -> entries in modules = [ ... ]
    # Create synthetic entry nodes like "flake::surface"
    # and link them to module paths / external module identifiers.
    m_cfgs = re.search(r'nixosConfigurations\s*=\s*\{(?P<body>.*?)\};', text, re.DOTALL)
    if m_cfgs:
        cfg_body = m_cfgs.group("body")
        for cm in RE_FLAKE_NIXOSCONFIG.finditer(cfg_body):
            name = cm.group("name")
            body = cm.group("body")
            entry = f"flake::nixosConfigurations.{name}"
            nodes.add(entry)

            mm = RE_FLAKE_MODULES_LIST.search(body)
            if mm:
                mods = mm.group("body")
                for tm in RE_TOKEN.finditer(mods):
                    tok = tm.group(1).strip()
                    if tok.startswith("./") or tok.startswith("../"):
                        tgt_abs = os.path.normpath(os.path.join(os.path.dirname(flake_path), tok))
                        if is_inside_root(tgt_abs) and os.path.exists(tgt_abs):
                            edges.append((entry, rel(tgt_abs), "flake-mod"))
                        else:
                            edges.append((entry, f"external:{tok}", "flake-mod"))
                    else:
                        edges.append((entry, f"external:{tok}", "flake-mod"))

            # Also connect flake.nix -> this entry node (nice for graph readability)
            edges.append(("flake.nix", entry, "defines"))

    # (2) overlays.default callPackage ./pkgs/... (to show package wiring)
    for om in RE_FLAKE_OVERLAY_CALLPKG.finditer(text):
        p = om.group("p")
        tgt_abs = norm_callpackage_target(flake_path, p)
        if is_inside_root(tgt_abs) and os.path.exists(tgt_abs):
            edges.append(("flake.nix", rel(tgt_abs), "flake-callPackage"))
        else:
            edges.append(("flake.nix", f"external:{p}", "flake-callPackage"))

    # (3) home-manager.users.<name> = import ./home.nix
    for hm in RE_HM_USERS_IMPORT.finditer(text):
        p = hm.group("p")
        tgt_abs = os.path.normpath(os.path.join(os.path.dirname(flake_path), p))
        if is_inside_root(tgt_abs) and os.path.exists(tgt_abs):
            edges.append(("flake.nix", rel(tgt_abs), "flake-hm"))
        else:
            edges.append(("flake.nix", f"external:{p}", "flake-hm"))

    nodes.add("flake.nix")
    return edges, nodes

# -----------------------------
# Graph building
# -----------------------------
def classify(node: str) -> str:
    if node.startswith("external:"):
        return "external"
    if node == "flake.nix" or node.startswith("flake::"):
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

CLUSTER_COLOR = {
    "flake":   "#c9c9c9",
    "hosts":   "#9ccfd8",
    "modules": "#a6e3a1",
    "profiles":"#f9e2af",
    "home":    "#fab387",
    "pkgs":    "#cba6f7",
    "tools":   "#94e2d5",
    "external":"#f38ba8",
    "misc":    "#b4befe",
}

EDGE_STYLE = {
    "imports":         {"style": "solid"},
    "import":          {"style": "solid"},
    "callPackage":     {"style": "dashed"},
    "flake-mod":       {"style": "bold"},
    "defines":         {"style": "dotted"},
    "flake-callPackage":{"style": "dashed"},
    "flake-hm":        {"style": "bold"},
}

def build_full_graph():
    nodes = set()
    edges = []

    # all local nix files
    for root, _, files in os.walk(ROOT):
        for f in files:
            if f.endswith(".nix"):
                fp = os.path.join(root, f)
                nodes.add(rel(fp))
                edges.extend(extract_edges_from_file(fp))

    # flake wiring edges
    flake_path = os.path.join(ROOT, "flake.nix")
    if os.path.exists(flake_path):
        fe, fn = extract_edges_from_flake(flake_path)
        edges.extend(fe)
        nodes |= fn

    # include endpoints
    for s, d, _ in edges:
        nodes.add(s); nodes.add(d)

    return nodes, edges

def reachability(nodes, edges):
    """Reachable local files from flake entry nodes (and flake.nix)."""
    adj = defaultdict(list)
    for s, d, _ in edges:
        adj[s].append(d)

    # entrypoints: flake::nixosConfigurations.*
    starts = [n for n in nodes if n.startswith("flake::nixosConfigurations.")]
    if not starts:
        starts = ["flake.nix"]

    seen = set()
    q = deque(starts)
    while q:
        cur = q.popleft()
        if cur in seen:
            continue
        seen.add(cur)
        for nxt in adj.get(cur, []):
            if nxt not in seen:
                q.append(nxt)

    # Only count local nix files as "reachable footprint"
    local_nix = {n for n in nodes if not n.startswith("external:") and n.endswith(".nix")}
    reachable_local = {n for n in seen if n in local_nix}

    return reachable_local, local_nix

def render_svg(nodes, edges, out_base="nixos-nerves"):
    g = Digraph("nixos_nerves", format="svg")
    g.attr(
        rankdir="LR",
        splines="ortho",
        concentrate="true",
        fontname="JetBrains Mono",
        fontsize="10",
        labelloc="t",
        label="NixOS Repo Nerves (flake wiring + imports + callPackage)",
    )
    g.attr("node", shape="box", style="rounded,filled", fontname="JetBrains Mono", fontsize="9")
    g.attr("edge", arrowsize="0.6")

    # clusters
    clusters = defaultdict(list)
    for n in nodes:
        clusters[classify(n)].append(n)

    for cname, members in clusters.items():
        sg = Digraph(name=f"cluster_{cname}")
        sg.attr(
            label=cname,
            color=CLUSTER_COLOR.get(cname, "#cccccc"),
            fontname="JetBrains Mono",
            fontsize="11",
            style="rounded",
        )
        fill = CLUSTER_COLOR.get(cname, "#ffffff")
        for n in sorted(members):
            sg.node(n, label=n, fillcolor=fill)
        g.subgraph(sg)

    for s, d, k in edges:
        st = EDGE_STYLE.get(k, {"style": "solid"})
        # only label the flake-mod edges; everything else is readable by style
        label = k if k in ("flake-mod",) else ""
        g.edge(s, d, label=label, **st)

    dot_path = os.path.join(ROOT, f"{out_base}.dot")
    svg_path = os.path.join(ROOT, f"{out_base}.svg")
    g.save(dot_path)
    g.render(filename=os.path.join(ROOT, out_base), cleanup=False)
    return dot_path, svg_path

def write_report(nodes, edges, out_name="nixos-nerves.report.txt"):
    indeg = Counter()
    outdeg = Counter()
    for s, d, _ in edges:
        outdeg[s] += 1
        indeg[d] += 1

    reachable_local, local_nix = reachability(nodes, edges)
    orphans = sorted(local_nix - reachable_local)

    report_path = os.path.join(ROOT, out_name)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("NixOS Nerves Report\n")
        f.write("===================\n\n")
        f.write(f"Root: {ROOT}\n")
        f.write(f"Nodes: {len(nodes)}\n")
        f.write(f"Edges: {len(edges)}\n\n")

        f.write(f"Local .nix files: {len(local_nix)}\n")
        f.write(f"Reachable from flake entrypoints: {len(reachable_local)}\n")
        f.write(f"Unreachable (true orphans): {len(orphans)}\n\n")

        f.write("Top 15 most depended-on (in-degree):\n")
        for n, c in indeg.most_common(15):
            f.write(f"  {c:>4}  {n}\n")

        f.write("\nTop 15 biggest importers/wirers (out-degree):\n")
        for n, c in outdeg.most_common(15):
            f.write(f"  {c:>4}  {n}\n")

        f.write("\nUnreachable local .nix files (orphans):\n")
        for n in orphans:
            f.write(f"  {n}\n")

    return report_path

def main():
    nodes, edges = build_full_graph()
    dot_path, svg_path = render_svg(nodes, edges)
    report_path = write_report(nodes, edges)

    print("Wrote:")
    print(f"  {dot_path}")
    print(f"  {svg_path}")
    print(f"  {report_path}")

if __name__ == "__main__":
    main()
