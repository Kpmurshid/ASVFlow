"""DADA2 read processing and ASV table results."""

import sys
from pathlib import Path

import pandas as pd
import plotly.express as px
import streamlit as st

sys.path.insert(0, str(Path(__file__).parent.parent))
from components.navigation import render_sidebar_navigation
from components.presentation import render_page_header, section_heading, style_figure

st.set_page_config(page_title="DADA2 Results", layout="wide")
render_sidebar_navigation()
render_page_header("DADA2 Processing", "Follow read retention, inspect chimera filtering, and explore the final ASV table.", "dna")
if "scanner" not in st.session_state or st.session_state.scanner is None:
    st.error("No run selected. Please go to the Home page and select a run.")
    st.stop()
scanner = st.session_state.scanner

tab1, tab2, tab3 = st.tabs(["Read Tracking", "Chimera Stats", "ASV Table"])

with tab1:
    section_heading("Read tracking", "Per-sample read counts emitted by DADA2 at each available processing stage.")
    track_df = scanner.get_dada2_track_reads()
    if track_df is not None:
        if track_df.empty:
            st.info("The read tracking file is present but contains no samples.")
        else:
            numeric_cols = [c for c in track_df.columns if c != "sample_id" and pd.api.types.is_numeric_dtype(track_df[c])]
            metric_cols = st.columns(min(4, len(numeric_cols) + 1))
            with metric_cols[0]:
                st.metric("Samples", len(track_df))
            for col, name in zip(metric_cols[1:], numeric_cols[:len(metric_cols)-1]):
                with col:
                    st.metric(f"Total {name}", f"{track_df[name].sum():,.0f}")
            if "sample_id" in track_df and "nonchim" in track_df:
                fig = px.bar(track_df, x="sample_id", y="nonchim", labels={"sample_id": "Sample", "nonchim": "Non-chimeric reads"},
                             title="Non-chimeric reads per sample", color_discrete_sequence=["#087e8b"], hover_data=numeric_cols)
                fig.update_xaxes(tickangle=-35)
                st.plotly_chart(style_figure(fig), use_container_width=True)
            with st.expander("Read tracking data", expanded=True):
                st.dataframe(track_df, use_container_width=True, hide_index=True)
    else:
        st.info(scanner.artifact_status_message("dada2", "track_reads", "DADA2 read tracking"))

with tab2:
    section_heading("Chimera removal", "Summary values and sample tracking are shown exactly as recorded in the DADA2 outputs.")
    chimera_df = scanner.get_dada2_chimera_stats()
    track_df = scanner.get_dada2_track_reads()
    if chimera_df is not None:
        stats = dict(zip(chimera_df.get("metric", []), chimera_df.get("value", [])))
        pairs = [("Input ASVs", "asvs_before"), ("Retained ASVs", "asvs_after"),
                 ("Chimeric reads", "reads_chimeric"), ("Chimeric reads (%)", "pct_chimeric_reads")]
        cols = st.columns(4)
        for col, (label, key) in zip(cols, pairs):
            with col:
                value = stats.get(key)
                st.metric(label, f"{float(value):,.1f}%" if key.endswith("pct_chimeric_reads") and value is not None else (f"{float(value):,.0f}" if value is not None else "—"))
        if stats.get("reads_before") is not None and stats.get("reads_chimeric") is not None:
            before, removed = float(stats["reads_before"]), float(stats["reads_chimeric"])
            retained = max(before - removed, 0)
            fig = px.bar(x=["Reads"], y=[retained], title="Read retention after chimera removal",
                         labels={"x": "", "y": "Sequences"}, color_discrete_sequence=["#13a58a"])
            fig.update_traces(name="Retained", showlegend=False, hovertemplate="Retained: %{y:,}<extra></extra>")
            fig.add_bar(x=["Reads"], y=[removed], name="Removed as chimeric", marker_color="#d58a27",
                        hovertemplate="Removed: %{y:,}<extra></extra>")
            fig.update_layout(barmode="stack")
            st.plotly_chart(style_figure(fig, 350), use_container_width=True)
        with st.expander("Detailed chimera statistics", expanded=True):
            st.dataframe(chimera_df, use_container_width=True, hide_index=True)
        if track_df is not None and {"sample_id", "nonchim"}.issubset(track_df.columns):
            st.caption("Per-sample retained reads are available in Read Tracking.")
    else:
        st.info(scanner.artifact_status_message("dada2", "chimera_stats", "DADA2 chimera statistics"))

with tab3:
    section_heading("ASV sequence table", "Filter sample columns and search ASV identifiers while retaining the complete export.")
    seqtab_df = scanner.get_dada2_seqtab()
    if seqtab_df is not None:
        c1, c2, c3 = st.columns(3)
        with c1: st.metric("ASVs", f"{len(seqtab_df):,}")
        with c2: st.metric("Samples", f"{len(seqtab_df.columns):,}")
        with c3: st.metric("Total abundance", f"{seqtab_df.to_numpy().sum():,.0f}")
        totals = seqtab_df.sum(axis=0).sort_values(ascending=False)
        fig = px.bar(x=totals.index, y=totals.values, labels={"x": "Sample", "y": "Reads"},
                     title="Reads per sample", color_discrete_sequence=["#2878d0"])
        fig.update_xaxes(tickangle=-35)
        st.plotly_chart(style_figure(fig, 350), use_container_width=True)
        left, right = st.columns([1, 2])
        with left:
            query = st.text_input("Search ASV ID", key="asv_search")
            sample_options = st.multiselect("Samples", seqtab_df.columns.tolist(), default=seqtab_df.columns.tolist(), key="asv_samples")
            row_limit = st.selectbox("Rows", [50, 100, 250, "All"], index=0)
        display_df = seqtab_df.loc[seqtab_df.index.astype(str).str.contains(query, case=False, regex=False)] if query else seqtab_df
        display_df = display_df.loc[:, sample_options]
        if row_limit != "All":
            display_df = display_df.head(int(row_limit))
        with right:
            st.caption(f"Showing {len(display_df):,} ASVs × {len(display_df.columns):,} samples")
            st.dataframe(display_df, use_container_width=True, height=460)
        st.download_button(" Download full ASV table", seqtab_df.to_csv(), "seqtab_nochim.csv", "text/csv")
    else:
        st.info(scanner.artifact_status_message("dada2", "seqtab", "DADA2 ASV table"))
