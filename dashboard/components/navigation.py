"""Shared native sidebar navigation for Streamlit's legacy multipage app."""

import streamlit as st

from components.theme import apply_theme, render_brand


_PAGE_LINKS = (
    ("app.py", "Home", "🏠"),
    ("pages/1_🔬_QC_Results.py", "QC Results", "🔬"),
    ("pages/2_🧬_DADA2_Results.py", "DADA2 Results", "🧬"),
    ("pages/3_🦠_Taxonomy.py", "Taxonomy", "🦠"),
    ("pages/4_📊_Community_Analysis.py", "Community Analysis", "📊"),
    ("pages/5_🔍_Sample_Explorer.py", "Sample Explorer", "🔍"),
)


def render_sidebar_navigation():
    """Render the shared brand and six legacy multipage links."""
    apply_theme()
    with st.sidebar:
        render_brand()
        for page_path, label, icon in _PAGE_LINKS:
            st.page_link(
                page_path,
                label=label,
                icon=icon,
                use_container_width=True,
            )
