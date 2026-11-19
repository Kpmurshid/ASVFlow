"""Taxonomy assignment summaries and composition explorer."""

import sys
from pathlib import Path

import pandas as pd
import plotly.express as px
import streamlit as st

sys.path.insert(0, str(Path(__file__).parent.parent))
from components.navigation import render_sidebar_navigation
from components.presentation import render_page_header, section_heading, style_figure

st.set_page_config(page_title="Taxonomy", page_icon="🦠", layout="wide")
render_sidebar_navigation()
render_page_header("Taxonomic Classification", "Explore assignments by rank and compare taxon abundance across samples.", "🦠")
if "scanner" not in st.session_state or st.session_state.scanner is None:
    st.error("No run selected. Go to Home page.")
    st.stop()
scanner = st.session_state.scanner
tab1, tab2, tab3 = st.tabs(["📊 Overview", "🔬 Taxonomy Table", "📈 Composition"])

with tab1:
    section_heading("Assignment overview", "Classification totals are read from the pipeline taxonomy statistics.")
    stats_df = scanner.get_taxonomy_stats()
    if stats_df is not None:
        stats = dict(zip(stats_df["metric"], stats_df["value"]))
        total = float(stats.get("total_asvs", 0) or 0)
        ranks = ["Kingdom", "Phylum", "Class", "Order", "Family", "Genus"]
        available = [(r, float(stats[f"classified_{r.lower()}" ])) for r in ranks if f"classified_{r.lower()}" in stats]
        cols = st.columns(4)
        for col, (label, key) in zip(cols, [("Total ASVs", "total_asvs"), ("Kingdom", "classified_kingdom"), ("Phylum", "classified_phylum"), ("Genus", "classified_genus")]):
            with col:
                val = stats.get(key)
                st.metric(label, f"{float(val):,.0f}" if val is not None else "—")
        if "pct_classified_genus" in stats:
            st.metric("Classified at genus", f"{float(stats['pct_classified_genus']):.1f}%")
        if available and total > 0:
            rank_df = pd.DataFrame({"Rank": [r for r, _ in available], "ASVs": [v for _, v in available],
                                    "Classified (%)": [v / total * 100 for _, v in available]})
            fig = px.bar(rank_df, x="Rank", y="Classified (%)", hover_data=["ASVs"],
                         title="Classification coverage by taxonomic rank", color="Rank")
            fig.update_yaxes(range=[0, 100], title="ASVs classified (%)")
            st.plotly_chart(style_figure(fig, 360), use_container_width=True)
        with st.expander("Taxonomy statistics", expanded=False):
            st.dataframe(stats_df, use_container_width=True, hide_index=True)
    else:
        st.warning("Taxonomy statistics are not available yet.")

with tab2:
    section_heading("Taxonomy table", "Search ASV identifiers and narrow the table to a taxonomic assignment.")
    tax_df = scanner.get_taxonomy()
    if tax_df is not None:
        c1, c2 = st.columns([1, 2])
        ranks = [r for r in ["Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species"] if r in tax_df.columns]
        with c1:
            rank = st.selectbox("Filter rank", ["All"] + ranks)
            taxon = st.selectbox("Assignment", ["All"] + sorted(tax_df[rank].dropna().astype(str).unique())) if rank != "All" else "All"
        with c2:
            query = st.text_input("Search ASV or sequence", key="taxonomy_search")
        display = tax_df.copy()
        if rank != "All" and taxon != "All":
            display = display[display[rank].astype(str) == taxon]
        if query:
            mask = display.astype(str).apply(lambda col: col.str.contains(query, case=False, regex=False)).any(axis=1)
            display = display[mask]
        st.caption(f"Showing {len(display):,} of {len(tax_df):,} assignments")
        st.dataframe(display, use_container_width=True, height=480, hide_index=True)
        st.download_button("📥 Download taxonomy table", tax_df.to_csv(index=False), "taxonomy.csv", "text/csv")
    else:
        st.warning("Taxonomy table is not available yet.")

with tab3:
    section_heading("Taxonomic composition", "Aggregate observed ASV abundances by their assigned taxon.")
    tax_df = scanner.get_taxonomy()
    seqtab = scanner.get_dada2_seqtab()
    if tax_df is not None and seqtab is not None:
        ranks = [r for r in ["Phylum", "Class", "Order", "Family", "Genus"] if r in tax_df.columns]
        c1, c2, c3 = st.columns([1, 1, 1.5])
        with c1: rank = st.selectbox("Taxonomic rank", ranks, key="taxonomy_comp_rank")
        with c2: mode = st.selectbox("Abundance", ["Relative (%)", "Counts"])
        with c3: samples = st.multiselect("Samples", seqtab.columns.tolist(), default=seqtab.columns.tolist(), key="tax_comp_samples")
        lookup = tax_df.drop_duplicates("ASV_ID").set_index("ASV_ID")[rank]
        matrix = seqtab.loc[:, samples]
        aggregated = {}
        for asv_id, abundance in matrix.iterrows():
            taxon = lookup.get(asv_id, None)
            taxon = str(taxon) if pd.notna(taxon) else f"Unclassified {rank}"
            aggregated[taxon] = aggregated.get(taxon, pd.Series(0, index=samples)) + abundance
        comp = pd.DataFrame(aggregated).T if aggregated else pd.DataFrame(columns=samples)
        relative = mode == "Relative (%)"
        denominators = comp.sum(axis=0)
        shown = comp.div(denominators.mask(denominators.eq(0)), axis=1).fillna(0) * 100 if relative else comp
        if len(shown) > 5:
            top_n = st.slider("Top taxa", 5, min(30, len(shown)), min(10, len(shown)))
        else:
            top_n = len(shown)
            st.caption(f"Showing all {top_n} available taxa.")
        means = shown.mean(axis=1).sort_values(ascending=False)
        keep = means.head(top_n).index
        plot_data = shown.loc[keep].copy()
        if len(means) > top_n:
            plot_data.loc["Other"] = shown.drop(index=keep).sum(axis=0)
        fig = px.bar(plot_data.T, x=plot_data.T.index, y=plot_data.T.columns, barmode="stack",
                     labels={"x": "Sample", "y": "Abundance (%)" if relative else "Read count", "variable": rank},
                     title=f"{rank} composition by sample", color_discrete_sequence=None)
        fig.update_xaxes(tickangle=-35)
        st.plotly_chart(style_figure(fig, 440), use_container_width=True)
        st.dataframe(shown.sort_index(), use_container_width=True, height=380)
        st.download_button("📥 Download composition table", shown.to_csv(), f"composition_{rank.lower()}_{'relabund' if relative else 'counts'}.csv", "text/csv")
    else:
        st.info("Composition requires both the taxonomy table and ASV abundance table.")
