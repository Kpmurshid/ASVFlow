import streamlit as st
import sys
from pathlib import Path
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

sys.path.insert(0, str(Path(__file__).parent.parent))
from parsers import OutputScanner

st.set_page_config(page_title="Community Analysis", page_icon="📊", layout="wide")
st.title("📊 Community Analysis")

if 'scanner' not in st.session_state:
    st.error("No run selected. Go to Home page.")
    st.stop()

scanner = st.session_state.scanner
outputs = scanner.scan_available_outputs()

# Check if community analysis is available
if not any(outputs['community'].values()):
    st.warning("⚠️ Community analysis not available")
    st.info("""Community analysis is **optional** in ASVFlow.

    To enable it, run the pipeline with:
    ```
    nextflow run main.nf --run_community true --metadata metadata.tsv ...
    ```

    Community analysis provides:
    - Alpha diversity metrics (Observed, Chao1, Shannon, Simpson)
    - Beta diversity with PCoA ordination (Bray-Curtis, Jaccard)
    - Taxonomic composition summaries
    - Statistical testing (PERMANOVA)
    """)
    st.stop()

tab1, tab2, tab3 = st.tabs(["📈 Alpha Diversity", "🗺️ Beta Diversity", "🧬 Composition"])

with tab1:
    st.subheader("Alpha Diversity Metrics")

    alpha_df = scanner.get_alpha_diversity()

    if alpha_df is not None:
        st.success(f"✅ Alpha diversity calculated for {len(alpha_df)} samples")

        # Summary statistics
        valid_samples = alpha_df[alpha_df['status'] == 'ok']

        if len(valid_samples) > 0:
            col1, col2, col3, col4 = st.columns(4)

            metrics = ['Observed', 'Chao1', 'Shannon', 'Simpson']
            for col, metric in zip([col1, col2, col3, col4], metrics):
                if metric in valid_samples.columns:
                    mean_val = valid_samples[metric].mean()
                    with col:
                        st.metric(f"Mean {metric}", f"{mean_val:.2f}")

            st.divider()

            # Box plots for each metric
            st.markdown("### Alpha Diversity Distribution")

            metric_select = st.selectbox("Select metric", metrics)

            if 'group' in valid_samples.columns:
                fig = px.box(valid_samples, x='group', y=metric_select,
                           title=f"{metric_select} by Group",
                           points="all")
            else:
                fig = px.box(valid_samples, y=metric_select,
                           title=f"{metric_select} Distribution",
                           points="all")

            st.plotly_chart(fig, use_container_width=True)

            # Full data table
            st.markdown("### Full Alpha Diversity Table")
            st.dataframe(alpha_df, use_container_width=True)

            csv = alpha_df.to_csv(index=False)
            st.download_button("📥 Download Alpha Diversity", csv,
                             "alpha_diversity.csv", "text/csv")
        else:
            st.warning("No valid samples with alpha diversity data")
            st.dataframe(alpha_df, use_container_width=True)
    else:
        st.warning("⏳ Alpha diversity not yet available")

with tab2:
    st.subheader("Beta Diversity - PCoA Ordination")

    metric = st.radio("Distance metric", ["Bray-Curtis", "Jaccard"], horizontal=True)
    metric_key = 'bray' if metric == "Bray-Curtis" else 'jaccard'

    pcoa_df = scanner.get_beta_diversity_pcoa(metric=metric_key)

    if pcoa_df is not None:
        st.success(f"✅ {metric} PCoA coordinates available")

        st.markdown(f"### PCoA Plot - {metric}")

        # Check if we have PC1 and PC2
        if 'PC1' in pcoa_df.columns and 'PC2' in pcoa_df.columns:

            if 'group' in pcoa_df.columns:
                fig = px.scatter(pcoa_df, x='PC1', y='PC2', color='group',
                               hover_data=['sample_id'],
                               title=f"PCoA - {metric}")
            else:
                fig = px.scatter(pcoa_df, x='PC1', y='PC2',
                               hover_data=['sample_id'],
                               title=f"PCoA - {metric}")

            fig.update_traces(marker=dict(size=10))
            fig.update_layout(width=800, height=600)
            st.plotly_chart(fig, use_container_width=True)

            # Coordinates table
            st.markdown("### PCoA Coordinates")
            st.dataframe(pcoa_df, use_container_width=True)

            csv = pcoa_df.to_csv(index=False)
            st.download_button(f"📥 Download {metric} PCoA", csv,
                             f"pcoa_{metric_key}.csv", "text/csv")
        else:
            st.warning("PCoA coordinates incomplete")
            st.dataframe(pcoa_df, use_container_width=True)
    else:
        st.warning(f"⏳ {metric} PCoA not yet available")

with tab3:
    st.subheader("Taxonomic Composition from Community Module")

    rank = st.selectbox("Taxonomic rank", ['Phylum', 'Genus'], key='comm_rank')
    rank_lower = rank.lower()

    comp_df = scanner.get_taxonomic_composition(rank=rank_lower, abundance_type='relabund')

    if comp_df is not None:
        st.success(f"✅ {rank}-level composition available")

        st.markdown(f"### Relative Abundance at {rank} Level")

        # Stacked bar chart
        fig = px.bar(comp_df.T, x=comp_df.T.index, y=comp_df.T.columns,
                    title=f"{rank} Composition Across Samples",
                    labels={'value': 'Relative Abundance (%)', 'index': 'Sample'})
        fig.update_layout(xaxis_tickangle=-45)
        st.plotly_chart(fig, use_container_width=True)

        # Data table
        st.markdown("### Composition Data (%)")
        st.dataframe(comp_df, use_container_width=True)

        csv = comp_df.to_csv()
        st.download_button(f"📥 Download {rank} Composition", csv,
                         f"composition_{rank_lower}.csv", "text/csv")
    else:
        st.warning(f"⏳ {rank} composition not yet available")

st.divider()
st.caption("""💡 **About Community Analysis:**
- Alpha diversity: within-sample diversity
- Beta diversity: between-sample differences
- PCoA: Principal Coordinates Analysis for visualization
- Requires --run_community true and metadata file
""")
