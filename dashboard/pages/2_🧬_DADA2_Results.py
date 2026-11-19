import streamlit as st
import sys
from pathlib import Path
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

sys.path.insert(0, str(Path(__file__).parent.parent))
from parsers import OutputScanner
from components.navigation import render_sidebar_navigation

st.set_page_config(page_title="DADA2 Results", page_icon="🧬", layout="wide")
render_sidebar_navigation()
st.title("🧬 DADA2 Processing Results")

if 'scanner' not in st.session_state or st.session_state.scanner is None:
    st.error("No run selected. Please go to the Home page and select a run.")
    st.stop()

scanner = st.session_state.scanner
outputs = scanner.scan_available_outputs()

tab1, tab2, tab3 = st.tabs(["📊 Read Tracking", "🔬 Chimera Stats", "🧬 ASV Table"])

with tab1:
    st.subheader("Read Tracking Through Processing")
    track_df = scanner.get_dada2_track_reads()

    if track_df is not None:
        st.success(f"✅ {len(track_df)} samples")
        st.dataframe(track_df, use_container_width=True)

        if len(track_df) > 0:
            fig = px.bar(track_df, x='sample_id', y='nonchim',
                        title="Non-chimeric Reads per Sample")
            fig.update_layout(xaxis_tickangle=-45)
            st.plotly_chart(fig, use_container_width=True)

            col1, col2, col3 = st.columns(3)
            with col1:
                st.metric("Total Samples", len(track_df))
            with col2:
                st.metric("Total Reads", f"{track_df['nonchim'].sum():,}")
            with col3:
                st.metric("Mean/Sample", f"{track_df['nonchim'].mean():.0f}")
    else:
        st.warning("⏳ Read tracking not available")

with tab2:
    st.subheader("Chimera Removal Statistics")
    chimera_df = scanner.get_dada2_chimera_stats()

    if chimera_df is not None:
        st.success("✅ Chimera statistics available")
        chimera_dict = dict(zip(chimera_df['metric'], chimera_df['value']))

        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.metric("ASVs Before", f"{chimera_dict.get('asvs_before', 0):,}")
        with col2:
            st.metric("ASVs After", f"{chimera_dict.get('asvs_after', 0):,}")
        with col3:
            st.metric("Reads After", f"{chimera_dict.get('reads_after', 0):,}")
        with col4:
            st.metric("% Chimeric", f"{chimera_dict.get('pct_chimeric_reads', 0)}%")

        st.dataframe(chimera_df, use_container_width=True)
    else:
        st.warning("⏳ Chimera stats not available")

with tab3:
    st.subheader("ASV Sequence Table")
    seqtab_df = scanner.get_dada2_seqtab()

    if seqtab_df is not None:
        st.success(f"✅ {len(seqtab_df)} ASVs × {len(seqtab_df.columns)} samples")

        col1, col2, col3 = st.columns(3)
        with col1:
            st.metric("Total ASVs", len(seqtab_df))
        with col2:
            st.metric("Total Reads", f"{seqtab_df.values.sum():,}")
        with col3:
            st.metric("Mean/Sample", f"{seqtab_df.sum(axis=0).mean():.0f}")

        st.markdown("### Reads per Sample")
        sample_totals = seqtab_df.sum(axis=0).sort_values(ascending=False)
        fig = px.bar(x=sample_totals.index, y=sample_totals.values,
                    title="Total Reads per Sample")
        fig.update_layout(xaxis_tickangle=-45)
        st.plotly_chart(fig, use_container_width=True)

        st.markdown("### ASV Table Preview (first 50)")
        st.dataframe(seqtab_df.head(50), use_container_width=True)

        csv = seqtab_df.to_csv()
        st.download_button("📥 Download Full ASV Table", csv,
                          "seqtab_nochim.csv", "text/csv")
    else:
        st.warning("⏳ ASV table not available")
