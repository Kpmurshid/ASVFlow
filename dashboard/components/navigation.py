"""Shared native sidebar navigation for Streamlit's legacy multipage app."""

import streamlit as st

from components.theme import apply_theme, render_brand
from components.presentation import apply_page_css
from components.icons import icon_data_uri


_PAGE_LINKS = (
    ("app.py", "Home", "house"),
    ("pages/1_QC_Results.py", "QC Results", "microscope"),
    ("pages/2_DADA2_Results.py", "DADA2 Results", "dna"),
    ("pages/3_Taxonomy.py", "Taxonomy", "tags"),
    ("pages/4_Community_Analysis.py", "Community Analysis", "chart-no-axes-combined"),
    ("pages/5_Sample_Explorer.py", "Sample Explorer", "search"),
    ("pages/6_Phylogenetic_Analysis.py", "Phylogenetic Analysis", "git-branch"),
)


def render_sidebar_navigation():
    """Render the shared brand and dashboard page links."""
    apply_theme()
    apply_page_css()
    with st.sidebar:
        render_brand()
        for page_path, label, icon in _PAGE_LINKS:
            st.page_link(
                page_path,
                label=label,
                use_container_width=True,
            )
        icons_css = "\n".join(
            f'[data-testid="stSidebarNav"] a[data-testid="stPageLink-NavLink"]:nth-of-type({i})::before {{'
            f'content:""; width:1.1rem; height:1.1rem; flex:none; margin-right:.55rem; '
            f'background-color:currentColor; -webkit-mask:{icon_data_uri(icon)} center/contain no-repeat; '
            f'mask:{icon_data_uri(icon)} center/contain no-repeat; }}'
            for i, (_, _, icon) in enumerate(_PAGE_LINKS, 1)
        )
        st.markdown(f"<style>{icons_css}</style>", unsafe_allow_html=True)
