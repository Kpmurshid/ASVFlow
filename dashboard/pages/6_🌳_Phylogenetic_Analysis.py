"""Interactive views of the optional ASV phylogeny."""
import sys
from pathlib import Path

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

sys.path.insert(0, str(Path(__file__).parent.parent))
from components.navigation import render_sidebar_navigation
from components.presentation import render_page_header, section_heading, style_figure
from utils.phylogeny import merge_taxonomy_tables, parse_newick, tree_geometry


def _leaf_nodes(node):
    if not node["children"]:
        return [node]
    return [leaf for child in node["children"] for leaf in _leaf_nodes(child)]

st.set_page_config(page_title="Phylogenetic Analysis", page_icon="🌳", layout="wide")
render_sidebar_navigation()
render_page_header("Phylogenetic Analysis", "Explore ASV relationships, branch distances, and taxonomy annotations.", "🌳")
if "scanner" not in st.session_state or st.session_state.scanner is None:
    st.error("No run selected. Go to Home page.")
    st.stop()

scanner = st.session_state.scanner
outputs = scanner.scan_available_outputs()["phylogeny"]
tree_path = outputs["tree"]
status_path = Path(scanner.outdir) / "phylogeny" / "phylogeny_status.txt"
pipeline_status = status_path.read_text().strip() if status_path.is_file() else ""
if tree_path is None:
    state = scanner.get_artifact_status("phylogeny", "tree")
    if pipeline_status == "empty_input":
        st.info("No nonchimeric ASV sequences were available, so no Newick tree was produced.")
    elif state == "Pending":
        st.info("Phylogenetic analysis is pending for this run. Enable it with `--run_phylogenetic_analysis true`.")
    elif state == "Missing (failed/partial run)":
        st.info("The phylogenetic tree is missing from this failed or partial run.")
    else:
        st.info("Phylogenetic analysis is unavailable for this run. Enable it with `--run_phylogenetic_analysis true`.")
    st.stop()

tree_text = tree_path.read_text().strip()
if pipeline_status == "insufficient_sequences":
    st.info("Only one ASV was available. The single-leaf Newick file is available to download.")
    st.download_button("Download Newick", tree_text, "asv_tree.nwk", "text/plain")
    st.stop()
try:
    root = parse_newick(tree_text)
except (ValueError, RecursionError):
    st.error("The Newick file exists but is invalid or could not be parsed.")
    st.stop()


def load_taxonomy():
    frames = []
    for relative in ("taxonomy/taxonomy.tsv", "taxonomy/taxonomy_species.tsv"):
        path = Path(scanner.outdir) / relative
        if path.is_file():
            try:
                frames.append(pd.read_csv(path, sep="\t", dtype=str, keep_default_na=False))
            except (OSError, ValueError, pd.errors.ParserError):
                continue
    return merge_taxonomy_tables(frames)


taxonomy = load_taxonomy()
section_heading("ASV phylogeny", "FastTree topology and branch lengths are shown as inferred; the tree is unrooted.")
if not taxonomy:
    st.caption("Taxonomy annotations are unavailable for this run. ASV identifiers remain available in labels and hover details.")

rank_options = ["Genus", "Species", "Family", "Phylum", "Order", "Class", "Kingdom"]
available_ranks = [rank for rank in rank_options if any(record["ranks"].get(rank) for record in taxonomy.values())]
if any(record["ranks"].get("Taxonomy") for record in taxonomy.values()):
    available_ranks.append("Taxonomy")
if not available_ranks:
    available_ranks = ["Genus"]

c1, c2, c3, c4 = st.columns([1.1, 1.1, 1.1, 1.5])
with c1:
    layout = st.selectbox("Tree layout", ["Rectangular phylogram", "Circular", "Radial"], key="phylo_layout")
with c2:
    color_rank = st.selectbox("Color tips by", available_ranks, key="phylo_color_rank", disabled=not taxonomy)
with c3:
    label_mode = st.selectbox("Tip labels", ["ASV IDs", "Taxonomy names", "Both"], key="phylo_label_mode")
with c4:
    search = st.text_input("Search ASV or taxon", placeholder="e.g. ASV_0004 or Escherichia")

show_taxonomy = st.checkbox("Show taxonomy labels", value=bool(taxonomy), disabled=not taxonomy)
show_lengths = st.checkbox("Show branch length labels", value=False)
default_tip_labels = len([node for node in _leaf_nodes(root)]) <= 80
show_tip_labels = st.checkbox("Show tip labels", value=default_tip_labels,
                              help="For large trees, turn labels off to reduce overlap; hover still shows full details.")

branches, leaves, geometry = tree_geometry(root, taxonomy, color_rank, layout)
groups = sorted({leaf["color_group"] for leaf in leaves})
palette = ["#087e8b", "#2878d0", "#7456b8", "#13a58a", "#d58a27", "#d65363", "#607d8b", "#9c755f", "#edc948", "#bab0ab"]
colors = {group: ("#9aa7b2" if group == "Unclassified" else "#84929e" if group == "Mixed taxonomy" else palette[i % len(palette)])
          for i, group in enumerate(group for group in groups if group not in ("Unclassified", "Mixed taxonomy"))}
colors["Unclassified"] = "#9aa7b2"
colors["Mixed taxonomy"] = "#84929e"
query = search.strip().casefold()
for leaf in leaves:
    taxname = leaf["taxonomy"]
    searchable_taxonomy = " ".join([taxname] + list(leaf["ranks"].values())).casefold()
    if label_mode == "ASV IDs" or not show_taxonomy:
        leaf["display"] = leaf["name"]
    elif label_mode == "Taxonomy names":
        leaf["display"] = taxname or leaf["name"]
    else:
        leaf["display"] = f"{leaf['name']} · {taxname}" if taxname else leaf["name"]
    leaf["matches"] = not query or query in leaf["name"].casefold() or query in searchable_taxonomy
if query:
    match_count = sum(leaf["matches"] for leaf in leaves)
    st.caption(f"Search matches: {match_count} of {len(leaves)} ASVs. Nonmatching tips are dimmed.")

fig = go.Figure()
for group in groups:
    x_values, y_values, hover_values = [], [], []
    for branch in branches:
        if branch["color_group"] != group:
            continue
        for segment, kind in zip(branch["segments"], branch["segment_kinds"]):
            hover = (f"Branch length: {branch['length']:.6g}<br>Clade: {branch['color_group']}"
                     if kind == "branch" else "Layout connector (no branch length)")
            for x, y in segment:
                x_values.append(x); y_values.append(y)
                hover_values.append(hover)
            x_values.append(None); y_values.append(None); hover_values.append(None)
    if x_values:
        fig.add_trace(go.Scatter(
            x=x_values, y=y_values, mode="lines", name=group,
            line=dict(color=colors[group], width=1.7), customdata=hover_values,
            hovertemplate="%{customdata}<extra></extra>", showlegend=True,
        ))

for group in groups:
    members = [leaf for leaf in leaves if leaf["color_group"] == group]
    if not members:
        continue
    x_vals = [leaf["x"] for leaf in members]
    y_vals = [leaf["plot_y"] for leaf in members]
    marker_sizes = [13 if leaf["matches"] and query else 8 for leaf in members]
    marker_lines = ["#102a43" if leaf["matches"] and query else "white" for leaf in members]
    marker_widths = [2.4 if leaf["matches"] and query else 0.8 for leaf in members]
    marker_opacity = [1.0 if leaf["matches"] or not query else 0.2 for leaf in members]
    lineage = ["; ".join(f"{rank}: {value}" for rank, value in leaf["ranks"].items() if value) or "Unavailable"
               for leaf in members]
    customdata = [[leaf["name"], leaf["taxonomy"] or "Unavailable", group,
                   f"{leaf['branch_length']:.6g}", f"{leaf['distance']:.6g}", tax]
                  for leaf, tax in zip(members, lineage)]
    label_positions = [
        "middle right" if layout == "Rectangular phylogram" or leaf["x"] >= 0 else "middle left"
        for leaf in members
    ]
    fig.add_trace(go.Scatter(
        x=x_vals, y=y_vals, mode="markers+text" if show_tip_labels else "markers",
        text=[leaf["display"] for leaf in members], textposition=label_positions,
        textfont=dict(size=10), name=group, legendgroup=group, showlegend=False,
        marker=dict(size=marker_sizes, color=colors[group], line=dict(color=marker_lines, width=marker_widths), opacity=marker_opacity),
        customdata=customdata,
        hovertemplate="<b>%{customdata[0]}</b><br>Taxonomy: %{customdata[1]}<br>"
                      "Color group: %{customdata[2]}<br>Terminal branch: %{customdata[3]}<br>"
                      "Root-to-tip distance: %{customdata[4]}<br>%{customdata[5]}<extra></extra>",
    ))

if show_lengths:
    for branch in branches:
        x, y = branch["midpoint"]
        fig.add_trace(go.Scatter(x=[x], y=[y], mode="text", text=[f"{branch['length']:.3g}"],
                                 textfont=dict(size=8, color="#40566b"), hoverinfo="skip", showlegend=False))

height = max(500, min(1250, 300 + 17 * len(leaves)))
fig = style_figure(fig, height)
if layout == "Rectangular phylogram":
    fig.update_layout(dragmode="pan", margin=dict(l=25, r=300, t=25, b=35),
                      xaxis=dict(title="Cumulative branch length", zeroline=False),
                      yaxis=dict(visible=False, autorange="reversed", fixedrange=False))
else:
    fig.update_layout(dragmode="pan", margin=dict(l=35, r=240, t=35, b=35),
                      xaxis=dict(visible=False, scaleanchor="y", scaleratio=1),
                      yaxis=dict(visible=False, scaleanchor="x", scaleratio=1))
fig.update_layout(legend=dict(title=color_rank if taxonomy else "Tips", orientation="v", x=1.01, y=1))

chart_state = st.plotly_chart(
    fig, use_container_width=True, on_select="rerun", selection_mode="points",
    config={"scrollZoom": True, "displaylogo": False, "modeBarButtonsToAdd": ["toImage"],
            "toImageButtonOptions": {"format": "png", "filename": "asv_phylogeny", "width": 2400,
                                     "height": max(1200, min(8000, len(leaves) * 24)), "scale": 2}},
)

selected_id = None
try:
    points = chart_state.selection.points
    if points:
        point = points[-1]
        curve = fig.data[point["curve_number"]]
        point_data = point.get("customdata")
        if point_data:
            selected_id = point_data[0]
        else:
            point_index = point.get("point_index", point.get("point_number"))
            selected_id = curve.customdata[point_index][0]
except (AttributeError, KeyError, IndexError, TypeError):
    pass
tip_ids = [leaf["name"] for leaf in leaves]
default_index = tip_ids.index(selected_id) if selected_id in tip_ids else 0
def tip_option(value):
    name = taxonomy.get(value, {}).get("label", "")
    return f"{value} — {name}" if name else value


selected_id = st.selectbox("Select an ASV tip for details", tip_ids, index=default_index, format_func=tip_option)
selected = next(leaf for leaf in leaves if leaf["name"] == selected_id)
detail_cols = st.columns([1, 2, 2, 2])
detail_cols[0].metric("ASV", selected["name"])
detail_cols[1].metric("Taxonomy", selected["taxonomy"] or "Unavailable")
detail_cols[2].metric("Terminal branch", f"{selected['branch_length']:.6g}")
detail_cols[3].metric("Root-to-tip distance", f"{selected['distance']:.6g}")

st.download_button("Download Newick", tree_text, "asv_tree.nwk", "text/plain")
st.caption("Use the chart camera control to export a high-resolution PNG; zoom and pan with the chart tools or scroll wheel.")
