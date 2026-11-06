import streamlit as st
import sys
from pathlib import Path
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

sys.path.insert(0, str(Path(__file__).parent.parent))
from parsers import OutputScanner

st.set_page_config(page_title="Taxonomy", page_icon="🦠", layout="wide")
st.title("🦠 Taxonomic Classification")

if 'scanner' not in st.session_state:
    st.error("No run selected. Go to Home page.")
    st.stop()

scanner = st.session_state.scanner

tab1, tab2, tab3 = st.tabs(["📊 Overview", "🔬 Taxonomy Table", "📈 Composition"])

with tab1:
    st.subheader("Taxonomy Assignment Overview")

    tax_stats = scanner.get_taxonomy_stats()

    if tax_stats is not None:
        st.success("✅ Taxonomy assignment complete")

        stats_dict = dict(zip(tax_stats['metric'], tax_stats['value']))

        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.metric("Total ASVs", f"{stats_dict.get('total_asvs', 0):,}")
        with col2:
            st.metric("Phylum Level", f"{stats_dict.get('classified_phylum', 0):,}")
        with col3:
            st.metric("Genus Level", f"{stats_dict.get('classified_genus', 0):,}")
        with col4:
            pct = stats_dict.get('pct_classified_genus', 0)
            st.metric("% at Genus", f"{pct}%")

        st.divider()
        st.markdown("### Classification Rate by Taxonomic Rank")

        ranks = ['Kingdom', 'Phylum', 'Class', 'Order', 'Family', 'Genus']
        counts = [stats_dict.get(f'classified_{r.lower()}', 0) for r in ranks]
        total = stats_dict.get('total_asvs', 1)
        pcts = [(c/total)*100 for c in counts]

        fig = go.Figure(data=[
            go.Bar(name='Classified', x=ranks, y=counts,
                  marker_color='steelblue')
        ])
        fig.update_layout(title="ASVs Classified at Each Rank",
                         yaxis_title="Number of ASVs")
        st.plotly_chart(fig, use_container_width=True)

        st.dataframe(tax_stats, use_container_width=True)
    else:
        st.warning("⏳ Taxonomy assignment not yet available")

with tab2:
    st.subheader("Taxonomy Table")

    tax_df = scanner.get_taxonomy()

    if tax_df is not None:
        st.success(f"✅ {len(tax_df)} ASVs classified")

        st.caption("Full taxonomic classification for all ASVs")

        # Filter options
        ranks = ['Kingdom', 'Phylum', 'Class', 'Order', 'Family', 'Genus']

        col1, col2 = st.columns(2)
        with col1:
            selected_rank = st.selectbox("Filter by rank", ['All'] + ranks)
        with col2:
            if selected_rank != 'All':
                unique_vals = tax_df[selected_rank].dropna().unique()
                selected_taxon = st.selectbox(f"Select {selected_rank}",
                                             ['All'] + sorted(unique_vals.tolist()))
            else:
                selected_taxon = 'All'

        # Apply filters
        display_df = tax_df.copy()
        if selected_rank != 'All' and selected_taxon != 'All':
            display_df = display_df[display_df[selected_rank] == selected_taxon]

        st.caption(f"Showing {len(display_df)} of {len(tax_df)} ASVs")
        st.dataframe(display_df, use_container_width=True, height=500)

        csv = tax_df.to_csv(index=False)
        st.download_button("📥 Download Taxonomy Table", csv,
                          "taxonomy.csv", "text/csv")
    else:
        st.warning("⏳ Taxonomy table not available")

with tab3:
    st.subheader("Taxonomic Composition")

    # Get both taxonomy and abundance data
    tax_df = scanner.get_taxonomy()
    seqtab_df = scanner.get_dada2_seqtab()

    if tax_df is not None and seqtab_df is not None:
        st.success("✅ Composition data available")

        # Select taxonomic rank
        rank = st.selectbox("Taxonomic rank",
                           ['Phylum', 'Class', 'Order', 'Family', 'Genus'],
                           index=0)

        # Merge taxonomy with abundance
        tax_lookup = tax_df.set_index('ASV_ID')[rank]

        # Aggregate by taxon
        composition = {}
        for asv_id in seqtab_df.index:
            taxon = tax_lookup.get(asv_id, 'Unclassified')
            if pd.isna(taxon):
                taxon = f'Unclassified_{rank}'

            if taxon not in composition:
                composition[taxon] = seqtab_df.loc[asv_id].values
            else:
                composition[taxon] += seqtab_df.loc[asv_id].values

        comp_df = pd.DataFrame(composition, index=seqtab_df.columns).T

        # Calculate relative abundance
        comp_rel = comp_df.div(comp_df.sum(axis=0), axis=1) * 100

        # Plot stacked bar chart
        st.markdown(f"### Relative Abundance at {rank} Level")

        # Keep top N taxa, group rest as "Other"
        top_n = st.slider("Show top N taxa", 5, 20, 10)

        mean_abund = comp_rel.mean(axis=1).sort_values(ascending=False)
        top_taxa = mean_abund.head(top_n).index.tolist()

        plot_df = comp_rel.loc[top_taxa].T

        fig = px.bar(plot_df, x=plot_df.index, y=plot_df.columns,
                    title=f"Top {top_n} {rank} across Samples",
                    labels={'value': 'Relative Abundance (%)', 'index': 'Sample'})
        fig.update_layout(xaxis_tickangle=-45, yaxis_title="Relative Abundance (%)")
        st.plotly_chart(fig, use_container_width=True)

        # Summary table
        st.markdown("### Composition Summary")
        summary = pd.DataFrame({
            'Taxon': comp_rel.index,
            'Mean_%': comp_rel.mean(axis=1).values,
            'Stdev_%': comp_rel.std(axis=1).values,
            'Total_Reads': comp_df.sum(axis=1).values
        }).sort_values('Mean_%', ascending=False)

        st.dataframe(summary, use_container_width=True)

        csv = comp_rel.to_csv()
        st.download_button("📥 Download Composition Table", csv,
                          f"composition_{rank}.csv", "text/csv")
    else:
        st.warning("⏳ Both taxonomy and ASV data required for composition")

st.caption("💡 Taxonomic classification uses SILVA database with DADA2's assignTaxonomy")
