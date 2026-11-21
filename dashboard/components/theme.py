"""Shared visual theme for ASVFlow Live pages."""

import base64
from pathlib import Path

import streamlit as st


_PUBLIC = Path(__file__).resolve().parents[1] / "public"


def _asset_url(name: str) -> str:
    path = _PUBLIC / name
    if not path.is_file():
        return ""
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:image/png;base64,{encoded}"


def apply_theme() -> None:
    """Apply the shared light scientific canvas and illustrated dark sidebar."""
    sidebar_bg = _asset_url("asvflow_sidebar_bg.png")
    sidebar_layer = (
        f"linear-gradient(180deg, rgba(7, 24, 43, .91), rgba(7, 34, 49, .94)), url('{sidebar_bg}')"
        if sidebar_bg else "linear-gradient(180deg, #07182b, #092b3b)"
    )
    st.markdown(f"""
    <style>
    :root {{
      --asv-navy: #102a43; --asv-teal: #087e8b; --asv-cyan: #20c5d8;
      --asv-blue: #2878d0; --asv-ink: #17324d; --asv-muted: #64798c;
      --asv-border: #dce7ee; --asv-surface: #ffffff; --asv-canvas: #f4f8fb;
    }}
    .stApp {{ background: var(--asv-canvas); color: var(--asv-ink); }}
    [data-testid="stHeader"] {{ background: rgba(244,248,251,.92); }}
    [data-testid="stSidebar"] {{
      background: {sidebar_layer}; background-size: cover; background-position: center top;
      border-right: 1px solid rgba(72, 210, 222, .24);
    }}
    [data-testid="stSidebar"] > div:first-child {{ background: transparent; }}
    section[data-testid="stSidebar"] {{ min-width:17rem; max-width:20rem; }}
    [data-testid="stSidebar"] [data-testid="stMarkdownContainer"] p,
    [data-testid="stSidebar"] label, [data-testid="stSidebar"] [data-testid="stCaptionContainer"] {{ color: #e5f3f7; }}
    [data-testid="stSidebar"] [data-testid="stSelectbox"] > label,
    [data-testid="stSidebar"] [data-testid="stCheckbox"] label {{ color: #e5f3f7; font-weight: 600; }}
    [data-testid="stSidebar"] [data-testid="stSelectbox"] [data-baseweb="select"] > div {{
      background: rgba(8, 27, 43, .78); border-color: rgba(105, 208, 221, .4); color: #f5fbfd;
    }}
    [data-testid="stSidebar"] [data-testid="stCheckbox"] {{ padding: .2rem 0; }}
    [data-testid="stSidebar"] .settings-container {{ margin:1.1rem 0 .5rem; padding-top:.8rem;
      border-top:1px solid rgba(140,220,228,.2); }}
    [data-testid="stSidebar"] [data-testid="stButton"] button {{
      border-color: rgba(105,208,221,.38); color: #eafaff; background: rgba(8,27,43,.72);
    }}
    [data-testid="stSidebar"] [data-testid="stButton"] button:hover {{
      border-color: var(--asv-cyan); color: #fff; background: rgba(13,126,139,.42);
    }}
    .asv-brand {{ text-align:center; padding: .55rem .5rem .9rem; margin: 0 0 1rem;
      border-bottom: 1px solid rgba(140,220,228,.24); }}
    .asv-brand img {{ width: 156px; max-width:100%; height: auto; display:block; margin: 0 auto .6rem; }}
    .asv-brand-title {{ color:#fff; font-size:1.18rem; font-weight:750; letter-spacing:.02em; }}
    .asv-brand-sub {{ color:#a9cbd4; font-size:.76rem; margin-top:.15rem; }}
    [data-testid="stSidebar"] [data-testid="stPageLink-NavLink"] {{
      border-radius: 9px; margin: .22rem 0; padding: .58rem .7rem;
      border: 1px solid transparent; color:#dceef2;
    }}
    [data-testid="stSidebar"] [data-testid="stPageLink-NavLink"]:hover {{
      background: rgba(32,197,216,.13); border-color:rgba(32,197,216,.28); color:#fff;
    }}
    [data-testid="stSidebar"] [data-testid="stPageLink-NavLink"][aria-current="page"] {{
      background: linear-gradient(90deg,rgba(32,197,216,.22),rgba(32,197,216,.08));
      border-color:rgba(32,197,216,.43); color:#fff; box-shadow:inset 3px 0 #20c5d8;
    }}
    .asv-sidebar-footer {{ text-align:center; margin-top:1.1rem; padding:.8rem .3rem 0;
      border-top:1px solid rgba(140,220,228,.2); color:#91b6c0; font-size:.69rem; line-height:1.6; }}
    .asv-hero {{ min-height:205px; padding:2.25rem 2.5rem; box-sizing:border-box;
      background-size:cover; background-position:center; border:1px solid #d6e7ee;
      border-radius:17px; box-shadow:0 8px 24px rgba(17,55,82,.08); margin:0 0 1.35rem; }}
    .asv-hero-kicker {{ font-size:.7rem; font-weight:750; letter-spacing:.14em; color:#087e8b; margin-bottom:.6rem; }}
    .asv-hero h1 {{ color:#102a43; font-size:2.45rem; line-height:1.12; margin:0; font-weight:800; }}
    .asv-hero h1 span {{ color:#2878d0; }}
    .asv-hero p {{ color:#526b7d; font-size:1.02rem; margin:.55rem 0 0; }}
    .asv-section {{ color:#17324d; font-size:1.12rem; font-weight:750; margin:1.6rem 0 .65rem;
      padding-bottom:.55rem; border-bottom:1px solid #dce7ee; }}
    .asv-overview-card {{ min-height:93px; box-sizing:border-box; padding:1rem 1.1rem;
      border:1px solid #dce7ee; border-radius:12px; background:#fff;
      box-shadow:0 3px 12px rgba(17,55,82,.045); border-top:3px solid #20c5d8; }}
    .asv-overview-label {{ color:#657d8d; font-size:.68rem; letter-spacing:.11em; font-weight:750; }}
    .asv-overview-value {{ color:#17324d; font-size:1.06rem; font-weight:720; margin-top:.4rem; overflow-wrap:anywhere; }}
    .asv-metric-card {{ min-height:105px; display:flex; flex-direction:column; justify-content:center;
      padding:.85rem 1rem; border:1px solid #dce7ee; border-radius:12px; background:#fff;
      box-shadow:0 3px 12px rgba(17,55,82,.045); border-left:4px solid var(--metric-accent,#20c5d8); }}
    .asv-metric-label {{ color:#657d8d; font-size:.78rem; }}
    .asv-metric-value {{ color:var(--metric-accent,#20c5d8); font-size:1.7rem; font-weight:780; line-height:1.2; }}
    .asv-progress-track {{ height:8px; border-radius:8px; background:#e5edf2; overflow:hidden; }}
    .asv-progress-fill {{ height:100%; border-radius:8px; background:linear-gradient(90deg,#087e8b,#20c5d8); }}
    h1, h2, h3 {{ color:var(--asv-navy); letter-spacing:-.025em; }}
    [data-testid="stDataFrame"] {{ border:1px solid var(--asv-border); border-radius:11px; overflow:hidden; }}
    [data-testid="stExpander"] {{ border:1px solid var(--asv-border); border-radius:11px; background:#fff; }}
    [data-testid="stDownloadButton"] button {{ border-radius:8px; }}
    [class*="st-key-quick_access_"] button {{ min-height:145px; height:100%; white-space:pre-line;
      text-align:left; align-items:flex-start; justify-content:flex-start; line-height:1.55;
      padding:1rem 1.05rem; border-radius:13px; border:1px solid #d8e5ec; background:#fff;
      box-shadow:0 4px 13px rgba(17,55,82,.055); color:#17324d; }}
    [class*="st-key-quick_access_"] button:hover {{ transform:translateY(-2px); border-color:#60bdca;
      box-shadow:0 8px 18px rgba(17,55,82,.1); color:#102a43; }}
    [class*="st-key-quick_access_"][class*="_available"] button {{ border-top:3px solid #13a58a; }}
    [class*="st-key-quick_access_"][class*="_pending"] button {{ border-top:3px solid #d7a13b; }}
    [class*="st-key-quick_access_"][class*="_optional"] button {{ border-top:3px solid #78889a; }}
    [class*="st-key-quick_access_qc_"] button {{ border-top-color:#13a58a; }}
    [class*="st-key-quick_access_dada2_"] button {{ border-top-color:#2878d0; }}
    [class*="st-key-quick_access_taxonomy_"] button {{ border-top-color:#7456b8; }}
    [class*="st-key-quick_access_community_"] button {{ border-top-color:#087e8b; }}
    [class*="st-key-quick_access_reports_"] button {{ border-top-color:#1688b8; }}
    [class*="st-key-quick_access_sample_explorer_"] button {{ border-top-color:#ca8d25; }}
    @media (max-width: 700px) {{
      .asv-hero {{ min-height:178px !important; padding:1.4rem !important; }}
      .asv-hero h1 {{ font-size:1.8rem !important; }}
      [data-testid="stHorizontalBlock"] {{ flex-wrap:wrap; gap:.7rem; }}
      [data-testid="stHorizontalBlock"] > [data-testid="column"] {{ flex:1 1 calc(50% - .7rem) !important; min-width: min(100%, 230px); }}
    }}
    @media (max-width: 480px) {{
      [data-testid="stHorizontalBlock"] > [data-testid="column"] {{ flex-basis:100% !important; }}
    }}
    </style>
    """, unsafe_allow_html=True)


def render_brand() -> None:
    logo = _asset_url("mkp-logo-sm.png")
    logo_markup = (
        f'<img src="{logo}" alt="ASVFlow logo" width="156" '
        'style="max-width:100%;height:auto;display:block;margin:0 auto .6rem">'
        if logo else ""
    )
    st.markdown(
        f'<div class="asv-brand">{logo_markup}<div class="asv-brand-title">ASVFlow Live</div>'
        '<div class="asv-brand-sub">Interactive Results Explorer</div></div>',
        unsafe_allow_html=True,
    )


def render_home_header() -> None:
    image = _asset_url("asvflow_header_bg.png")
    background = f"url('{image}')" if image else "linear-gradient(100deg,#e8f4f7,#d9ebf7)"
    st.markdown(f"""
    <section class="asv-hero" style="background-image:linear-gradient(90deg,rgba(247,252,253,.96) 0%,rgba(247,252,253,.84) 46%,rgba(247,252,253,.18) 100%),{background};">
      <div class="asv-hero-kicker">ASVFLOW LIVE · SCIENTIFIC RESULTS EXPLORER</div>
      <h1>ASVFlow <span>Live</span> Dashboard</h1>
      <p>Interactive Pipeline Monitoring and Scientific Results Explorer</p>
    </section>
    """, unsafe_allow_html=True)
