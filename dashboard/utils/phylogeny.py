"""Newick parsing, taxonomy mapping, and geometry for ASV phylogeny views."""
import math

RANKS = ("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")


def parse_newick(source):
    """Parse FastTree's unquoted Newick while retaining every branch length."""
    text = source.strip()
    if not text.endswith(";"):
        raise ValueError("Newick tree must end with a semicolon")
    text = text[:-1]
    index = 0

    def read_label():
        nonlocal index
        start = index
        while index < len(text) and text[index] not in ",()":
            index += 1
        token = text[start:index].strip()
        label, separator, raw_length = token.rpartition(":")
        if separator:
            try:
                length = float(raw_length)
            except ValueError as exc:
                raise ValueError("Invalid Newick branch length") from exc
            if not math.isfinite(length) or length < 0:
                raise ValueError("Branch lengths must be finite and nonnegative")
        else:
            label, length = token, 0.0
        return label, length

    def subtree():
        nonlocal index
        children = []
        if index < len(text) and text[index] == "(":
            index += 1
            children.append(subtree())
            while index < len(text) and text[index] == ",":
                index += 1
                children.append(subtree())
            if index >= len(text) or text[index] != ")":
                raise ValueError("Unclosed Newick group")
            index += 1
        label, length = read_label()
        if not children and not label:
            raise ValueError("Newick leaf has no label")
        return {"name": label, "length": length, "children": children}

    if not text:
        raise ValueError("Newick tree is empty")
    root = subtree()
    if index != len(text):
        raise ValueError("Unexpected trailing Newick content")
    return root


def validate_newick(source):
    try:
        return bool(parse_newick(source))
    except (ValueError, RecursionError):
        return False


def taxonomy_mapping(table):
    """Map taxonomy TSV rows by ASV_ID, tolerating optional ranks and NA values."""
    if table is None or table.empty:
        return {}
    columns = {str(column).strip().lower(): column for column in table.columns}
    id_column = next((columns[key] for key in ("asv_id", "asv", "feature_id") if key in columns), None)
    if id_column is None:
        return {}
    rank_columns = {rank: columns.get(rank.lower()) for rank in RANKS}
    if not any(rank_columns.values()):
        taxonomy_column = next((columns[key] for key in ("taxonomy", "taxon") if key in columns), None)
        if taxonomy_column is None:
            return {}
        rank_columns["Taxonomy"] = taxonomy_column

    def clean(value):
        if value is None:
            return ""
        value = str(value).strip()
        if value.lower() in ("", "na", "nan", "none", "unclassified", "unknown"):
            return ""
        return value.replace("_", " ")

    mapping = {}
    for _, row in table.iterrows():
        asv_id = str(row[id_column]).strip() if row[id_column] is not None else ""
        if asv_id.lower() in ("", "na", "nan", "none"):
            asv_id = ""
        if not asv_id:
            continue
        ranks = {rank: clean(row[column]) if column is not None else "" for rank, column in rank_columns.items()}
        species, genus = ranks.get("Species", ""), ranks.get("Genus", "")
        if species and genus and not species.casefold().startswith(genus.casefold()):
            label = f"{genus} {species}"
        else:
            label = species or genus or ranks.get("Family") or ranks.get("Taxonomy", "")
        mapping[asv_id] = {"ranks": ranks, "label": label}
    return mapping


def merge_taxonomy_tables(tables):
    """Merge genus/species tables by ID, preferring populated values from later tables."""
    merged = {}
    for table in tables:
        for asv_id, record in taxonomy_mapping(table).items():
            target = merged.setdefault(asv_id, {"ranks": {rank: "" for rank in RANKS}, "label": ""})
            target["ranks"].update({rank: value for rank, value in record["ranks"].items() if value})
            target["label"] = (target["ranks"].get("Species") or target["ranks"].get("Genus")
                               or target["ranks"].get("Family") or target["ranks"].get("Taxonomy", ""))
            species, genus = target["ranks"].get("Species", ""), target["ranks"].get("Genus", "")
            if species and genus and not species.casefold().startswith(genus.casefold()):
                target["label"] = f"{genus} {species}"
    return merged


def read_fasta(source):
    records = {}
    name = None
    for line in source.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith(">"):
            name = line[1:].split()[0]
            if not name or name in records:
                raise ValueError("FASTA contains an empty or duplicate identifier")
            records[name] = ""
        elif name is None:
            raise ValueError("FASTA sequence appears before its identifier")
        else:
            records[name] += line
    return records


def read_sequence_table_ids(source):
    lines = [line for line in source.splitlines() if line.strip()]
    return [line.split("\t", 1)[0].lstrip("#") for line in lines[1:]] if lines else []


def tree_geometry(root, taxonomy=None, color_rank="Genus", layout="Rectangular phylogram"):
    """Return true tree branches/tips with cumulative FastTree branch distances."""
    taxonomy = taxonomy or {}
    leaves = []
    branches = []
    leaf_counter = 0
    angle_offset = -math.pi / 2 if layout == "Circular" else 0.0

    def decorate(node, parent_distance=0.0):
        nonlocal leaf_counter
        node["distance"] = parent_distance + node["length"]
        if not node["children"]:
            node["span"] = (leaf_counter, leaf_counter)
            node["y"] = float(leaf_counter)
            leaf_counter += 1
            record = taxonomy.get(node["name"], {})
            ranks = record.get("ranks", {})
            node["groups"] = {ranks.get(color_rank) or "Unclassified"}
            return
        for child in node["children"]:
            decorate(child, node["distance"])
        node["span"] = (node["children"][0]["span"][0], node["children"][-1]["span"][1])
        node["y"] = sum(child["y"] for child in node["children"]) / len(node["children"])
        node["groups"] = set().union(*(child["groups"] for child in node["children"]))

    decorate(root)
    count = max(leaf_counter, 1)

    if layout == "Radial":
        def assign_radial_angles(node, start, end):
            node["plot_angle"] = (start + end) / 2
            children = node["children"]
            if children:
                step = (end - start) / len(children)
                for index, child in enumerate(children):
                    assign_radial_angles(child, start + index * step, start + (index + 1) * step)
        assign_radial_angles(root, -math.pi / 2, 3 * math.pi / 2)

    def angle(node):
        if layout == "Radial":
            return node["plot_angle"]
        midpoint = (node["span"][0] + node["span"][1]) / 2
        return 2 * math.pi * midpoint / count + angle_offset

    def point(node):
        if layout == "Rectangular phylogram":
            return (node["distance"], node["y"])
        theta = angle(node)
        return (node["distance"] * math.cos(theta), node["distance"] * math.sin(theta))

    def branch_group(node):
        if len(node["groups"]) == 1:
            return next(iter(node["groups"]))
        return "Mixed taxonomy"

    def add_edges(node):
        for child in node["children"]:
            group = branch_group(child)
            if layout == "Rectangular phylogram":
                px, py = point(node)
                cx, cy = point(child)
                segments = [[(px, py), (px, cy)], [(px, cy), (cx, cy)]]
                midpoint = ((px + cx) / 2, cy)
            else:
                px, py = point(node)
                cx, cy = point(child)
                parent_angle, child_angle = angle(node), angle(child)
                delta = (child_angle - parent_angle + math.pi) % (2 * math.pi) - math.pi
                n_points = max(3, int(abs(delta) * 14) + 2)
                arc = []
                for i in range(n_points):
                    theta = parent_angle + delta * i / (n_points - 1)
                    arc.append((node["distance"] * math.cos(theta), node["distance"] * math.sin(theta)))
                radial = [(node["distance"] * math.cos(child_angle), node["distance"] * math.sin(child_angle)), (cx, cy)]
                segments = [arc, radial]
                midpoint = ((node["distance"] + child["distance"]) / 2 * math.cos(child_angle),
                            (node["distance"] + child["distance"]) / 2 * math.sin(child_angle))
            branches.append({"segments": segments, "segment_kinds": ["connector", "branch"],
                             "length": child["length"], "color_group": group,
                             "midpoint": midpoint, "child": child["name"] if not child["children"] else ""})
            add_edges(child)
    add_edges(root)

    max_distance = max((leaf["distance"] for leaf in _walk_leaves(root)), default=0.0)
    for node in _walk_leaves(root):
        record = taxonomy.get(node["name"], {})
        ranks = record.get("ranks", {})
        x, y = point(node)
        leaves.append({"name": node["name"], "taxonomy": record.get("label", ""), "ranks": ranks,
                       "branch_length": node["length"], "distance": node["distance"],
                       "x": x, "plot_y": y, "y": node["y"], "angle": angle(node),
                       "color_group": ranks.get(color_rank) or "Unclassified"})
    return branches, leaves, {"max_distance": max_distance, "leaf_count": len(leaves)}


def _walk_leaves(node):
    if not node["children"]:
        yield node
    for child in node["children"]:
        yield from _walk_leaves(child)
