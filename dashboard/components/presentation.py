"""Reusable presentation helpers for scientific results pages."""

import streamlit as st


PALETTE = ["#087e8b", "#2878d0", "#7456b8", "#13a58a", "#d58a27", "#d65363", "#607d8b"]


def render_page_header(title: str, subtitle: str, icon: str) -> None:
    """Render a compact results header on the shared light canvas."""
    st.markdown(
        f'<div class="asv-page-header"><div class="asv-page-icon">{icon}</div>'
        f'<div><div class="asv-page-kicker">ASVFLOW LIVE · RESULTS</div>'
        f'<h1>{title}</h1><p>{subtitle}</p></div></div>',
        unsafe_allow_html=True,
    )


def section_heading(title: str, caption: str = "") -> None:
    st.markdown(f'<div class="asv-section">{title}</div>', unsafe_allow_html=True)
    if caption:
        st.caption(caption)


def style_figure(fig, height: int = 430):
    """Apply the common ASVFlow Plotly canvas and typography."""
    fig.update_layout(
        template="plotly_white", height=height, colorway=PALETTE,
        paper_bgcolor="rgba(0,0,0,0)", plot_bgcolor="#ffffff",
        font=dict(family="Arial, sans-serif", color="#29465d", size=12),
        margin=dict(l=18, r=18, t=42, b=28),
        legend=dict(title_text="", bgcolor="rgba(255,255,255,.82)"),
        hoverlabel=dict(bgcolor="#102a43", font_color="#ffffff"),
    )
    fig.update_xaxes(showgrid=False, zeroline=False, automargin=True)
    fig.update_yaxes(gridcolor="#e8eff3", zeroline=False, automargin=True)
    return fig


def apply_page_css() -> None:
    st.markdown("""
    <style>
    .asv-page-header { display:flex; align-items:center; gap:1rem; padding:.35rem 0 1.1rem;
      margin-bottom:.65rem; border-bottom:1px solid #dce7ee; }
    .asv-page-icon { width:3.25rem; height:3.25rem; display:grid; place-items:center;
      border-radius:13px; background:linear-gradient(145deg,#e1f5f7,#e7f0fb); font-size:1.65rem;
      box-shadow:inset 0 0 0 1px #d2e8ed; }
    .asv-page-kicker { color:#087e8b; font-size:.67rem; font-weight:750; letter-spacing:.13em; }
    .asv-page-header h1 { margin:.12rem 0 .15rem; font-size:1.85rem; line-height:1.15; }
    .asv-page-header p { color:#64798c; margin:0; font-size:.92rem; }
    [data-testid="stMetric"] { background:#fff; padding:.8rem 1rem; border:1px solid #dce7ee;
      border-radius:11px; box-shadow:0 3px 12px rgba(17,55,82,.04); }
    [data-testid="stMetricLabel"] { color:#64798c; }
    [data-testid="stPlotlyChart"] { border:1px solid #e1eaf0; border-radius:12px;
      background:#fff; padding:.35rem; box-shadow:0 3px 12px rgba(17,55,82,.035); }
    div[data-baseweb="tab-list"] { gap:.35rem; }
    button[data-baseweb="tab"] { border-radius:8px 8px 0 0; }
    @media (max-width:700px) { .asv-page-header h1 {font-size:1.45rem;} }
    </style>
    """, unsafe_allow_html=True)

