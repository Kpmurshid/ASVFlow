"""Community diversity and composition exploration."""

import sys
from pathlib import Path

import pandas as pd
import plotly.express as px
import streamlit as st

sys.path.insert(0, str(Path(__file__).parent.parent))
from components.navigation import render_sidebar_navigation
from components.presentation import render_page_header, section_heading, style_figure

st.set_page_config(page_title="Community Analysis", page_icon="📊", layout="wide")
render_sidebar_navigation()
render_page_header("Community Analysis", "Compare within-sample diversity, between-sample structure, and taxonomic composition.", "📊")
if "scanner" not in st.session_state or st.session_state.scanner is None:
    st.error("No run selected. Go to Home page.")
    st.stop()
scanner = st.session_state.scanner
outputs = scanner.scan_available_outputs()
if not any(outputs["community"].values()):
    status = scanner.get_artifact_status("community", "alpha_diversity")
    if status == "Pending":
        st.info("Community analysis outputs are pending while this run is active. Enable them with `--run_community_analysis true` and provide sample metadata.")
    elif status == "Missing (failed/partial run)":
        st.info("Community analysis outputs are missing from this failed or partial run.")
    else:
        st.info("Community analysis is optional and unavailable for this completed run. Enable it with `--run_community_analysis true` and provide sample metadata.")
    st.stop()

tab1, tab2, tab3 = st.tabs(["📈 Alpha Diversity", "🗺️ Beta Diversity", "🧬 Composition"])

with tab1:
    section_heading("Alpha diversity", "Per-sample diversity estimates from the pipeline output.")
    alpha = scanner.get_alpha_diversity()
    if alpha is not None:
        valid = alpha[alpha["status"].astype(str).str.lower() == "ok"] if "status" in alpha else alpha
        metrics = [m for m in ["Observed", "Chao1", "Shannon", "Simpson"] if m in valid]
        if not valid.empty and metrics:
            cols = st.columns(len(metrics))
            for col, metric in zip(cols, metrics):
                with col: st.metric(f"Mean {metric}", f"{pd.to_numeric(valid[metric], errors='coerce').mean():.2f}")
            metric = st.selectbox("Diversity metric", metrics)
            chart = valid.copy()
            chart[metric] = pd.to_numeric(chart[metric], errors="coerce")
            if "group" in chart and chart["group"].notna().any():
                fig = px.box(chart, x="group", y=metric, color="group", points="all", title=f"{metric} by group")
            else:
                fig = px.strip(chart, y=metric, hover_name="sample_id" if "sample_id" in chart else None,
                               title=f"{metric} across samples", color_discrete_sequence=["#087e8b"])
            fig.update_yaxes(title=metric)
            st.plotly_chart(style_figure(fig, 400), use_container_width=True)
        else:
            st.info("No valid alpha-diversity measurements are available.")
        with st.expander("Alpha diversity table", expanded=True):
            st.dataframe(alpha, use_container_width=True, hide_index=True)
        st.download_button("📥 Download alpha diversity", alpha.to_csv(index=False), "alpha_diversity.csv", "text/csv")
    else:
        st.info(scanner.artifact_status_message("community", "alpha_diversity", "Alpha diversity"))

with tab2:
    section_heading("Beta diversity", "Inspect principal coordinate analysis for the selected distance metric.")
    metric = st.radio("Distance metric", ["Bray-Curtis", "Jaccard"], horizontal=True)
    key = "bray" if metric == "Bray-Curtis" else "jaccard"
    pcoa = scanner.get_beta_diversity_pcoa(metric=key)
    if pcoa is not None:
        coordinate_cols = [c for c in ["PC1", "PC2"] if c in pcoa]
        valid = pcoa.dropna(subset=coordinate_cols) if coordinate_cols else pcoa.copy()
        if {"PC1", "PC2"}.issubset(pcoa.columns) and not valid.empty:
            group_col = "group" if "group" in valid and valid["group"].notna().any() else None
            fig = px.scatter(valid, x="PC1", y="PC2", color=group_col, hover_name="sample_id" if "sample_id" in valid else None,
                             text="sample_id" if "sample_id" in valid else None,
                             title=f"{metric} PCoA", color_discrete_sequence=None)
            fig.update_traces(marker=dict(size=11, line=dict(width=1, color="white")), textposition="top center")
            stats_path = Path(scanner.outdir) / "community" / "beta_diversity_stats.tsv"
            if stats_path.is_file():
                try:
                    stats = pd.read_csv(stats_path, sep="\t")
                    row1 = stats[(stats["metric"] == metric) & (stats["PC"] == 1)]
                    row2 = stats[(stats["metric"] == metric) & (stats["PC"] == 2)]
                    xlab = f"PC1 ({float(row1.iloc[0]['variance_explained']):.1f}%)" if not row1.empty else "PC1"
                    ylab = f"PC2 ({float(row2.iloc[0]['variance_explained']):.1f}%)" if not row2.empty else "PC2"
                    fig.update_xaxes(title=xlab); fig.update_yaxes(title=ylab)
                except (OSError, ValueError, KeyError, IndexError, TypeError):
                    fig.update_xaxes(title="PC1"); fig.update_yaxes(title="PC2")
            else:
                fig.update_xaxes(title="PC1"); fig.update_yaxes(title="PC2")
            st.plotly_chart(style_figure(fig, 500), use_container_width=True)
            # Display PERMANOVA only when the corresponding analysis output exists.
            perm_path = Path(scanner.outdir) / "community" / f"permanova_{key}.tsv"
            if perm_path.is_file():
                try:
                    perm = pd.read_csv(perm_path, sep="\t", index_col=0)
                    if not perm.empty:
                        st.caption(f"{metric} PERMANOVA (pipeline output)")
                        st.dataframe(perm, use_container_width=True)
                except (OSError, ValueError):
                    st.info("PERMANOVA output exists but could not be read.")
            with st.expander("PCoA coordinates", expanded=False):
                st.dataframe(pcoa, use_container_width=True, hide_index=True)
            st.download_button(f"📥 Download {metric} PCoA", pcoa.to_csv(index=False), f"pcoa_{key}.csv", "text/csv")
        else:
            st.info(f"{metric} coordinates do not contain usable PC1 and PC2 values.")
    else:
        artifact_key = "beta_bray" if key == "bray" else "beta_jaccard"
        st.info(scanner.artifact_status_message("community", artifact_key, f"{metric} PCoA"))

with tab3:
    section_heading("Community composition", "Explore pipeline-provided relative abundance or count tables.")
    c1, c2 = st.columns([1, 2])
    with c1: rank = st.selectbox("Taxonomic rank", ["Phylum", "Genus"], key="comm_rank")
    with c2: abundance = st.radio("Abundance", ["Relative (%)", "Counts"], horizontal=True, key="comm_abundance")
    rank_key = rank.lower()
    kind = "relabund" if abundance == "Relative (%)" else "counts"
    composition = scanner.get_taxonomic_composition(rank=rank_key, abundance_type=kind)
    if composition is not None:
        samples = st.multiselect("Samples", composition.columns.tolist(), default=composition.columns.tolist(), key="community_samples")
        data = composition.loc[:, samples]
        if len(data) > 5:
            top_n = st.slider("Top taxa by mean abundance", 5, min(30, len(data)), min(10, len(data)), key="community_top")
        else:
            top_n = len(data)
            st.caption(f"Showing all {top_n} available taxa.")
        selected = data.mean(axis=1).sort_values(ascending=False).head(top_n).index
        plot = data.loc[selected].copy()
        if len(data) > top_n:
            plot.loc["Other"] = data.drop(index=selected).sum(axis=0)
        fig = px.bar(plot.T, x=plot.T.index, y=plot.T.columns, barmode="stack",
                     labels={"x": "Sample", "value": abundance, "variable": rank}, title=f"{rank} abundance by sample")
        fig.update_xaxes(tickangle=-35)
        st.plotly_chart(style_figure(fig, 450), use_container_width=True)
        st.dataframe(data, use_container_width=True, height=380)
        st.download_button(f"📥 Download {rank} {abundance.lower()}", composition.to_csv(), f"composition_{rank_key}_{kind}.csv", "text/csv")
    else:
        artifact_key = f"comp_{rank_key}_{kind}"
        st.info(scanner.artifact_status_message("community", artifact_key, f"{rank} {abundance.lower()} output"))
