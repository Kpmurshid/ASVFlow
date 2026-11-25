"""Focused per-sample exploration of ASV, taxonomy, and available metrics."""

import sys
from pathlib import Path

import pandas as pd
import plotly.express as px
import streamlit as st

sys.path.insert(0, str(Path(__file__).parent.parent))
from components.navigation import render_sidebar_navigation
from components.presentation import render_page_header, section_heading, style_figure

st.set_page_config(page_title="Sample Explorer", layout="wide")
render_sidebar_navigation()
render_page_header("Sample Explorer", "Inspect one sample at a time across its abundance, taxonomy, and diversity results.", "search")
if "scanner" not in st.session_state or st.session_state.scanner is None:
    st.error("No run selected. Go to Home page.")
    st.stop()
scanner = st.session_state.scanner
seqtab = scanner.get_dada2_seqtab()
if seqtab is None:
    st.info(scanner.artifact_status_message("dada2", "seqtab", "Sample exploration and DADA2 ASV table"))
    st.stop()

samples = seqtab.columns.tolist()
if not samples:
    st.info("The ASV table contains no sample columns.")
    st.stop()
selected_sample = st.selectbox("Sample", samples)
counts = pd.to_numeric(seqtab[selected_sample], errors="coerce").fillna(0)
positive = counts[counts > 0].sort_values(ascending=False)
total_reads = int(counts.sum())

section_heading("Sample summary", "Read totals and detected ASVs from the final non-chimeric ASV table.")
c1, c2, c3, c4 = st.columns(4)
with c1: st.metric("Sample ID", selected_sample)
with c2: st.metric("Total reads", f"{total_reads:,}")
with c3: st.metric("ASVs detected", f"{len(positive):,}")
with c4: st.metric("Top 10 ASVs", f"{positive.head(10).sum() / total_reads * 100:.1f}%" if total_reads else "—")

tab1, tab2, tab3 = st.tabs(["ASV Abundance", "Taxonomy", "Sample Context"])
with tab1:
    section_heading("ASV abundance", "Abundance distribution for this sample.")
    if not positive.empty:
        if len(positive) > 5:
            top_n = st.slider("ASVs to display", 5, min(50, len(positive)), min(20, len(positive)))
        else:
            top_n = len(positive)
            st.caption(f"Showing all {top_n} detected ASVs.")
        top = positive.head(top_n)
        chart_data = pd.DataFrame({"ASV_ID": top.index.astype(str), "Read_Count": top.values,
                                   "Relative_Abundance_%": (top.values / total_reads * 100).round(2) if total_reads else 0})
        fig = px.bar(chart_data, x="ASV_ID", y="Read_Count", labels={"ASV_ID": "ASV identifier", "Read_Count": "Read count"},
                     title=f"Top {len(top)} ASVs in {selected_sample}", color_discrete_sequence=["#2878d0"],
                     hover_data=["Relative_Abundance_%"])
        fig.update_xaxes(tickangle=-35)
        st.plotly_chart(style_figure(fig, 420), use_container_width=True)
        st.dataframe(pd.DataFrame({"ASV_ID": positive.index, "Read_Count": positive.values,
                                   "Relative_Abundance_%": (positive.values / total_reads * 100).round(2)}),
                     use_container_width=True, height=380, hide_index=True)
    else:
        st.info("No non-zero ASV counts were recorded for this sample.")

with tab2:
    section_heading("Taxonomy", "Top ASVs joined to their existing taxonomy assignments, when available.")
    taxonomy = scanner.get_taxonomy()
    if taxonomy is not None:
        top = positive.head(30)
        table = pd.DataFrame({"ASV_ID": top.index, "Read_Count": top.values})
        table["Relative_Abundance_%"] = (table["Read_Count"] / total_reads * 100).round(2) if total_reads else 0
        taxonomy_cols = [c for c in ["Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species"] if c in taxonomy]
        if "ASV_ID" in taxonomy:
            table = table.merge(taxonomy[["ASV_ID"] + taxonomy_cols].drop_duplicates("ASV_ID"), on="ASV_ID", how="left")
        st.dataframe(table, use_container_width=True, height=440, hide_index=True)
        if "Genus" in table:
            genus = (table.assign(Genus=table["Genus"].fillna("Unclassified"))
                     .groupby("Genus", as_index=False)["Read_Count"].sum()
                     .sort_values("Read_Count", ascending=False).head(10))
            fig = px.bar(genus, x="Genus", y="Read_Count", title="Most abundant genera among displayed ASVs",
                         color_discrete_sequence=["#7456b8"])
            fig.update_xaxes(tickangle=-35)
            st.plotly_chart(style_figure(fig, 350), use_container_width=True)
    else:
        st.info("Taxonomy assignments are not available; ASV identifiers and abundance are shown.")
        st.dataframe(pd.DataFrame({"ASV_ID": positive.head(30).index, "Read_Count": positive.head(30).values}),
                     use_container_width=True, hide_index=True)

with tab3:
    section_heading("Sample context", "Compare total reads across samples and show diversity only when available.")
    totals = seqtab.sum(axis=0).sort_values(ascending=False)
    rank = int(totals.index.get_loc(selected_sample)) + 1
    a, b = st.columns(2)
    with a: st.metric("Read count rank", f"{rank} of {len(totals)}")
    with b: st.metric("Read count percentile", f"{(len(totals) - rank) / len(totals) * 100:.1f}%")
    colors = ["#20c5d8" if sample == selected_sample else "#9bb6c8" for sample in totals.index]
    fig = px.bar(x=totals.index, y=totals.values, labels={"x": "Sample", "y": "Total reads"},
                 title="Read depth across samples", color_discrete_sequence=["#9bb6c8"])
    fig.update_traces(marker_color=colors, hovertemplate="%{x}<br>%{y:,} reads<extra></extra>")
    fig.update_xaxes(tickangle=-35)
    st.plotly_chart(style_figure(fig, 400), use_container_width=True)
    alpha = scanner.get_alpha_diversity()
    if alpha is not None and {"sample_id", "Shannon"}.issubset(alpha.columns):
        row = alpha[alpha["sample_id"].astype(str) == str(selected_sample)]
        if not row.empty:
            st.metric("Shannon diversity", f"{float(row.iloc[0]['Shannon']):.2f}")
    tracking = scanner.get_dada2_track_reads()
    if tracking is not None and {"sample_id", "nonchim"}.issubset(tracking.columns):
        row = tracking[tracking["sample_id"].astype(str) == str(selected_sample)]
        if not row.empty:
            st.metric("Non-chimeric reads (tracking)", f"{float(row.iloc[0]['nonchim']):,.0f}")
