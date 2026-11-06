import streamlit as st
import sys
from pathlib import Path
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

sys.path.insert(0, str(Path(__file__).parent.parent))
from parsers import OutputScanner

st.set_page_config(page_title="Sample Explorer", page_icon="🔍", layout="wide")
st.title("🔍 Sample Explorer")

if 'scanner' not in st.session_state:
    st.error("No run selected. Go to Home page.")
    st.stop()

scanner = st.session_state.scanner

# Get available samples from ASV table
seqtab_df = scanner.get_dada2_seqtab()

if seqtab_df is None:
    st.warning("⏳ ASV table not yet available")
    st.info("Sample explorer requires completed DADA2 processing.")
    st.stop()

samples = seqtab_df.columns.tolist()

st.subheader("Select Sample")
selected_sample = st.selectbox("Sample ID", samples)

if selected_sample:
    st.divider()
    st.subheader(f"📊 Sample: {selected_sample}")

    # Get sample data
    sample_asvs = seqtab_df[selected_sample]
    sample_asvs = sample_asvs[sample_asvs > 0].sort_values(ascending=False)

    # Summary metrics
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric("Total Reads", f"{sample_asvs.sum():,}")

    with col2:
        st.metric("ASVs Detected", len(sample_asvs))

    with col3:
        if len(sample_asvs) > 0:
            top10_pct = (sample_asvs.head(10).sum() / sample_asvs.sum()) * 100
            st.metric("Top 10 ASVs %", f"{top10_pct:.1f}%")

    with col4:
        # Get alpha diversity if available
        alpha_df = scanner.get_alpha_diversity()
        if alpha_df is not None and selected_sample in alpha_df['sample_id'].values:
            shannon = alpha_df[alpha_df['sample_id'] == selected_sample]['Shannon'].values[0]
            st.metric("Shannon Index", f"{shannon:.2f}")
        else:
            st.metric("Shannon Index", "N/A")

    st.divider()

    # ASV abundance distribution
    st.markdown("### ASV Abundance Distribution")

    fig = px.bar(x=sample_asvs.index, y=sample_asvs.values,
                title=f"ASV Abundance in {selected_sample}",
                labels={'x': 'ASV_ID', 'y': 'Read Count'})
    fig.update_layout(xaxis_tickangle=-45, showlegend=False)
    st.plotly_chart(fig, use_container_width=True)

    # Top ASVs with taxonomy
    st.markdown("### Top ASVs with Taxonomy")

    tax_df = scanner.get_taxonomy()

    if tax_df is not None:
        top_asvs = sample_asvs.head(20)

        # Merge with taxonomy
        top_df = pd.DataFrame({
            'ASV_ID': top_asvs.index,
            'Read_Count': top_asvs.values
        })

        # Add taxonomy
        tax_lookup = tax_df.set_index('ASV_ID')
        for col in ['Phylum', 'Class', 'Order', 'Family', 'Genus']:
            if col in tax_lookup.columns:
                top_df[col] = top_df['ASV_ID'].map(tax_lookup[col])

        # Calculate percentage
        top_df['Percentage'] = (top_df['Read_Count'] / sample_asvs.sum() * 100).round(2)

        st.dataframe(top_df, use_container_width=True)

        # Taxonomic composition pie chart at genus level
        if 'Genus' in top_df.columns:
            st.markdown("### Taxonomic Composition (Top 10 Genera)")

            genus_abund = {}
            for idx, row in top_df.iterrows():
                genus = row['Genus'] if pd.notna(row['Genus']) else 'Unclassified'
                count = row['Read_Count']
                genus_abund[genus] = genus_abund.get(genus, 0) + count

            genus_df = pd.DataFrame({
                'Genus': list(genus_abund.keys()),
                'Abundance': list(genus_abund.values())
            }).sort_values('Abundance', ascending=False).head(10)

            fig = px.pie(genus_df, values='Abundance', names='Genus',
                        title=f"Genus-level Composition (Top 10)")
            st.plotly_chart(fig, use_container_width=True)
    else:
        st.info("Taxonomy not available - showing ASV IDs only")
        st.dataframe(pd.DataFrame({
            'ASV_ID': sample_asvs.head(20).index,
            'Read_Count': sample_asvs.head(20).values,
            'Percentage': (sample_asvs.head(20) / sample_asvs.sum() * 100).round(2).values
        }), use_container_width=True)

    st.divider()

    # Compare to other samples
    st.markdown("### Compare to Other Samples")

    all_sample_totals = seqtab_df.sum(axis=0).sort_values(ascending=False)
    current_rank = list(all_sample_totals.index).index(selected_sample) + 1

    col1, col2 = st.columns(2)

    with col1:
        st.info(f"**Read Count Rank:** {current_rank} of {len(samples)}")

    with col2:
        percentile = ((len(samples) - current_rank) / len(samples)) * 100
        st.info(f"**Percentile:** {percentile:.1f}%")

    # Bar chart showing this sample in context
    fig = go.Figure()

    colors = ['steelblue' if s != selected_sample else 'red' for s in all_sample_totals.index]

    fig.add_trace(go.Bar(
        x=all_sample_totals.index,
        y=all_sample_totals.values,
        marker_color=colors
    ))

    fig.update_layout(
        title=f"Read Counts Across All Samples (selected sample in red)",
        xaxis_title="Sample",
        yaxis_title="Total Reads",
        xaxis_tickangle=-45,
        showlegend=False
    )

    st.plotly_chart(fig, use_container_width=True)

st.caption("💡 Select different samples to explore their ASV composition and compare across the dataset")
