"""
ASVFlow Live Dashboard - Home/Overview Page

Main application entry point with navigation and overview.
Phase 2: Multi-page application for scientific results exploration.
"""

import streamlit as st
import sys
import argparse
from pathlib import Path
import time

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from parsers import NextflowMonitor, OutputScanner
from components import render_overview


def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='ASVFlow Live Dashboard')
    parser.add_argument('--outdir', default='results', help='Output directory to monitor')

    # Parse args after -- separator (Streamlit compatibility)
    args = parser.parse_args(sys.argv[2:] if len(sys.argv) > 2 and sys.argv[1] == '--' else [])
    return args


def initialize_session_state():
    """Initialize session state variables for cross-page communication"""
    if 'selected_run' not in st.session_state:
        st.session_state.selected_run = None
    if 'scanner' not in st.session_state:
        st.session_state.scanner = None
    if 'monitor' not in st.session_state:
        st.session_state.monitor = None
    if 'project_dir' not in st.session_state:
        st.session_state.project_dir = None


def main():
    """Main dashboard application"""

    # Page configuration
    st.set_page_config(
        page_title="ASVFlow Live",
        page_icon="🧬",
        layout="wide",
        initial_sidebar_state="expanded"
    )

    # Initialize session state
    initialize_session_state()

    # Parse arguments
    args = parse_args()

    # Initialize monitors
    project_dir = Path.cwd()
    st.session_state.project_dir = project_dir
    monitor = NextflowMonitor(project_dir=project_dir)
    st.session_state.monitor = monitor

    # ========== SIDEBAR STYLING ==========
    st.sidebar.markdown("""
    <style>
    /* Brand container */
    [data-testid="stSidebar"] .brand-container {
        background-color: rgba(128, 128, 128, 0.05);
        border: 1px solid rgba(128, 128, 128, 0.1);
        border-radius: 8px;
        padding: 1.25rem;
        margin-bottom: 1.5rem;
        text-align: center;
    }
    [data-testid="stSidebar"] .brand-container img {
        margin-bottom: 0.75rem;
    }
    .brand-title {
        font-size: 1.25rem;
        font-weight: 600;
        margin: 0.75rem 0 0.25rem 0;
    }
    .brand-sub {
        font-size: 0.875rem;
        opacity: 0.7;
        margin: 0;
    }

    /* Section containers */
    [data-testid="stSidebar"] .panel-container {
        background-color: rgba(128, 128, 128, 0.05);
        border: 1px solid rgba(128, 128, 128, 0.1);
        border-radius: 8px;
        padding: 1rem;
        margin-bottom: 1rem;
    }
    .panel-label {
        font-size: 0.75rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.5px;
        opacity: 0.6;
        margin-bottom: 0.75rem;
        display: block;
    }

    /* Navigation cards */
    .nav-card {
        background-color: rgba(128, 128, 128, 0.03);
        border: 1px solid rgba(128, 128, 128, 0.1);
        border-radius: 6px;
        padding: 0.625rem 0.875rem;
        margin-bottom: 0.5rem;
        display: flex;
        align-items: center;
        gap: 0.625rem;
    }
    .nav-card-active {
        background-color: rgba(59, 130, 246, 0.1);
        border-left: 3px solid #3b82f6;
        padding-left: calc(0.875rem - 2px);
    }
    .nav-card-avail {
        border-left: 3px solid #16a34a;
        padding-left: calc(0.875rem - 2px);
    }
    .nav-card-pend {
        opacity: 0.5;
    }
    .nav-icon {
        font-size: 1.125rem;
        width: 1.5rem;
        text-align: center;
    }
    .nav-text {
        flex: 1;
        font-size: 0.875rem;
        font-weight: 500;
    }
    .nav-badge {
        font-size: 0.75rem;
        padding: 0.125rem 0.5rem;
        border-radius: 10px;
        background-color: rgba(34, 197, 94, 0.15);
        color: #16a34a;
    }

    /* Footer */
    [data-testid="stSidebar"] .footer-container {
        margin-top: 1.5rem;
        padding-top: 1rem;
        border-top: 1px solid rgba(128, 128, 128, 0.1);
        font-size: 0.75rem;
        opacity: 0.6;
        text-align: center;
    }
    </style>
    """, unsafe_allow_html=True)

    # ========== BRAND PANEL ==========
    logo_path = Path(__file__).parent / "public" / "mkp-logo-sm.png"
    brand_html = '<div class="brand-container">'
    if logo_path.exists():
        import base64
        with open(logo_path, "rb") as f:
            logo_b64 = base64.b64encode(f.read()).decode()
        brand_html += f'<img src="data:image/png;base64,{logo_b64}" width="120" />'
    brand_html += '<div class="brand-title">ASVFlow Live</div>'
    brand_html += '<div class="brand-sub">Interactive Results Explorer</div>'
    brand_html += '</div>'
    st.sidebar.markdown(brand_html, unsafe_allow_html=True)

    # ========== RUN SELECTOR ==========
    available_runs = monitor.list_runs()

    if not available_runs:
        st.sidebar.warning("No Nextflow runs found")
        st.warning("No ASVFlow runs detected in this directory.")
        st.info("Run ASVFlow with `nextflow run main.nf ...` to begin monitoring.")
        return

    # Format run options
    run_options = []
    for run in available_runs:
        icon = {'OK': '✓', 'ERR': '✗', '-': '◌'}.get(run['status'], '?')
        run_options.append(f"{icon} {run['run_name']} ({run['timestamp']})")

    st.sidebar.markdown('<div class="panel-container"><div class="panel-label">Run Selection</div></div>', unsafe_allow_html=True)
    selected_idx = st.sidebar.selectbox(
        "Select Run",
        range(len(run_options)),
        format_func=lambda i: run_options[i],
        index=len(run_options) - 1,
        label_visibility="collapsed"
    )

    selected_run = available_runs[selected_idx]
    outdir = monitor.get_run_outdir(selected_run)
    scanner = OutputScanner(outdir)
    st.session_state.selected_run = selected_run
    st.session_state.scanner = scanner

    # ========== NAVIGATION ==========
    outputs = scanner.scan_available_outputs()
    pages = [
        ("Overview", "🏠", True, True),
        ("QC Results", "🔬", any(outputs['qc'].values()), False),
        ("DADA2 Results", "🧬", any(outputs['dada2'].values()), False),
        ("Taxonomy", "🦠", any(outputs['taxonomy'].values()), False),
        ("Community Analysis", "📊", any(outputs['community'].values()), False),
        ("Sample Explorer", "🔍", any(outputs['dada2'].values()), False),
    ]

    nav_html = '<div class="panel-container"><div class="panel-label">Available Pages</div>'
    for name, icon, avail, active in pages:
        cls = "nav-card"
        if active:
            cls += " nav-card-active"
        elif avail:
            cls += " nav-card-avail"
        else:
            cls += " nav-card-pend"
        badge = '<div class="nav-badge">✓</div>' if (avail and not active) else ''
        nav_html += f'<div class="{cls}"><div class="nav-icon">{icon}</div><div class="nav-text">{name}</div>{badge}</div>'
    nav_html += '</div>'
    st.sidebar.markdown(nav_html, unsafe_allow_html=True)

    # ========== SETTINGS ==========
    st.sidebar.markdown('<div class="panel-container"><div class="panel-label">Settings</div></div>', unsafe_allow_html=True)
    auto_refresh = st.sidebar.checkbox(
        "Enable auto-refresh",
        value=(selected_run['status'] in ['-', 'RUNNING']),
        help="Periodically reload run metadata and task data"
    )

    if auto_refresh:
        refresh_interval = st.sidebar.slider(
            "Refresh interval (seconds)",
            min_value=2,
            max_value=30,
            value=5,
            help="How often to refresh the dashboard"
        )
        st.sidebar.caption(f"⟳ Refreshing every {refresh_interval}s")

    if st.sidebar.button("Refresh Now", use_container_width=True, type="secondary"):
        st.rerun()

    # ========== FOOTER ==========
    st.sidebar.markdown(f'''
    <div class="footer-container">
        <div><strong>ASVFlow Live Dashboard</strong></div>
        <div>Version 2.0.0</div>
        <div style="margin-top: 0.25rem;">Project: {project_dir.name}</div>
    </div>
    ''', unsafe_allow_html=True)

    # Main content area - Home/Overview
    # ========== HEADER SECTION ==========
    st.markdown("# ASVFlow Live Dashboard")
    st.caption("Interactive Pipeline Monitoring and Scientific Results Explorer")
    st.markdown("")  # Spacing

    # Run information banner - Compact cards
    col1, col2, col3 = st.columns([3, 2, 2])

    with col1:
        st.markdown(f"""
        <div style="background-color: rgba(59, 130, 246, 0.1); border-left: 3px solid #3b82f6;
                    padding: 0.75rem 1rem; border-radius: 6px;">
            <div style="font-size: 0.75rem; opacity: 0.7; margin-bottom: 0.25rem;">ACTIVE RUN</div>
            <div style="font-size: 1rem; font-weight: 600;">{selected_run['run_name']}</div>
        </div>
        """, unsafe_allow_html=True)

    with col2:
        status = selected_run['status']
        status_colors = {
            'OK': ('#16a34a', '#dcfce7', 'Completed'),
            'ERR': ('#dc2626', '#fee2e2', 'Failed'),
            '-': ('#3b82f6', '#dbeafe', 'Running'),
            'RUNNING': ('#3b82f6', '#dbeafe', 'Running')
        }
        color, bg_color, label = status_colors.get(status, ('#6b7280', '#f3f4f6', 'Unknown'))

        st.markdown(f"""
        <div style="background-color: {bg_color}; border-left: 3px solid {color};
                    padding: 0.75rem 1rem; border-radius: 6px;">
            <div style="font-size: 0.75rem; opacity: 0.7; margin-bottom: 0.25rem;">STATUS</div>
            <div style="font-size: 1rem; font-weight: 600; color: {color};">{label}</div>
        </div>
        """, unsafe_allow_html=True)

    with col3:
        st.markdown(f"""
        <div style="background-color: rgba(128, 128, 128, 0.05); border-left: 3px solid rgba(128, 128, 128, 0.3);
                    padding: 0.75rem 1rem; border-radius: 6px;">
            <div style="font-size: 0.75rem; opacity: 0.7; margin-bottom: 0.25rem;">STARTED</div>
            <div style="font-size: 1rem; font-weight: 600;">{selected_run['timestamp']}</div>
        </div>
        """, unsafe_allow_html=True)

    st.markdown("")  # Spacing
    st.markdown("")  # Spacing

    # Render overview component
    render_overview(monitor, scanner, selected_run)

    # ========== QUICK ACCESS SECTION ==========
    st.markdown('<div style="font-size: 1.1rem; font-weight: 600; margin-bottom: 1rem; margin-top: 2rem; padding-bottom: 0.5rem; border-bottom: 2px solid rgba(128, 128, 128, 0.1);">Quick Access</div>', unsafe_allow_html=True)

    st.caption("Navigate to detailed analysis pages")

    col1, col2, col3 = st.columns(3)

    with col1:
        if outputs['qc']['raw_multiqc']:
            st.markdown("""
            <div style="background-color: rgba(34, 197, 94, 0.1); border: 1px solid rgba(34, 197, 94, 0.2);
                        border-radius: 8px; padding: 1rem; text-align: center;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">✓</div>
                <div style="font-weight: 600;">QC Results</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Available</div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown("""
            <div style="background-color: rgba(128, 128, 128, 0.05); border: 1px solid rgba(128, 128, 128, 0.1);
                        border-radius: 8px; padding: 1rem; text-align: center; opacity: 0.6;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">○</div>
                <div style="font-weight: 600;">QC Results</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Pending</div>
            </div>
            """, unsafe_allow_html=True)

    with col2:
        if outputs['dada2']['seqtab']:
            st.markdown("""
            <div style="background-color: rgba(34, 197, 94, 0.1); border: 1px solid rgba(34, 197, 94, 0.2);
                        border-radius: 8px; padding: 1rem; text-align: center;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">✓</div>
                <div style="font-weight: 600;">DADA2 Results</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Available</div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown("""
            <div style="background-color: rgba(128, 128, 128, 0.05); border: 1px solid rgba(128, 128, 128, 0.1);
                        border-radius: 8px; padding: 1rem; text-align: center; opacity: 0.6;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">○</div>
                <div style="font-weight: 600;">DADA2 Results</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Pending</div>
            </div>
            """, unsafe_allow_html=True)

    with col3:
        if outputs['taxonomy']['taxonomy_table']:
            st.markdown("""
            <div style="background-color: rgba(34, 197, 94, 0.1); border: 1px solid rgba(34, 197, 94, 0.2);
                        border-radius: 8px; padding: 1rem; text-align: center;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">✓</div>
                <div style="font-weight: 600;">Taxonomy</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Available</div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown("""
            <div style="background-color: rgba(128, 128, 128, 0.05); border: 1px solid rgba(128, 128, 128, 0.1);
                        border-radius: 8px; padding: 1rem; text-align: center; opacity: 0.6;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">○</div>
                <div style="font-weight: 600;">Taxonomy</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Pending</div>
            </div>
            """, unsafe_allow_html=True)

    st.markdown("")  # Spacing

    # Second row for additional items
    col4, col5, col6 = st.columns(3)

    with col4:
        if outputs['community']['alpha_diversity']:
            st.markdown("""
            <div style="background-color: rgba(34, 197, 94, 0.1); border: 1px solid rgba(34, 197, 94, 0.2);
                        border-radius: 8px; padding: 1rem; text-align: center;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">✓</div>
                <div style="font-weight: 600;">Community Analysis</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Available</div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown("""
            <div style="background-color: rgba(128, 128, 128, 0.05); border: 1px solid rgba(128, 128, 128, 0.1);
                        border-radius: 8px; padding: 1rem; text-align: center; opacity: 0.5;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">○</div>
                <div style="font-weight: 600;">Community Analysis</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Optional</div>
            </div>
            """, unsafe_allow_html=True)

    with col5:
        if outputs['reports']['execution_report']:
            st.markdown("""
            <div style="background-color: rgba(34, 197, 94, 0.1); border: 1px solid rgba(34, 197, 94, 0.2);
                        border-radius: 8px; padding: 1rem; text-align: center;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">✓</div>
                <div style="font-weight: 600;">Nextflow Reports</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Available</div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown("""
            <div style="background-color: rgba(128, 128, 128, 0.05); border: 1px solid rgba(128, 128, 128, 0.1);
                        border-radius: 8px; padding: 1rem; text-align: center; opacity: 0.6;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">○</div>
                <div style="font-weight: 600;">Nextflow Reports</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Pending</div>
            </div>
            """, unsafe_allow_html=True)

    with col6:
        if outputs['dada2']['seqtab']:
            st.markdown("""
            <div style="background-color: rgba(34, 197, 94, 0.1); border: 1px solid rgba(34, 197, 94, 0.2);
                        border-radius: 8px; padding: 1rem; text-align: center;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">✓</div>
                <div style="font-weight: 600;">Sample Explorer</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Available</div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown("""
            <div style="background-color: rgba(128, 128, 128, 0.05); border: 1px solid rgba(128, 128, 128, 0.1);
                        border-radius: 8px; padding: 1rem; text-align: center; opacity: 0.6;">
                <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">○</div>
                <div style="font-weight: 600;">Sample Explorer</div>
                <div style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Pending</div>
            </div>
            """, unsafe_allow_html=True)

    st.markdown("")  # Spacing

    # ========== TASK DETAILS SECTION ==========
    st.markdown('<div style="font-size: 1.1rem; font-weight: 600; margin-bottom: 1rem; margin-top: 2rem; padding-bottom: 0.5rem; border-bottom: 2px solid rgba(128, 128, 128, 0.1);">Task Execution Details</div>', unsafe_allow_html=True)

    trace_df = scanner.get_execution_trace()

    if not trace_df.empty:
        st.caption(f"Showing {len(trace_df)} completed tasks from execution trace")

        # Display key columns
        display_cols = ['name', 'status', 'exit', 'duration', 'realtime', '%cpu', 'peak_rss']
        available_cols = [col for col in display_cols if col in trace_df.columns]

        if available_cols:
            # Add custom CSS for table
            st.markdown("""
            <style>
            div[data-testid="stDataFrame"] {
                border: 1px solid rgba(128, 128, 128, 0.1);
                border-radius: 8px;
                overflow: hidden;
            }
            div[data-testid="stDataFrame"] > div {
                border-radius: 8px;
            }
            </style>
            """, unsafe_allow_html=True)

            st.dataframe(
                trace_df[available_cols],
                use_container_width=True,
                height=400
            )
        else:
            st.dataframe(trace_df, use_container_width=True, height=400)

        # Download button
        csv = trace_df.to_csv(index=False)
        st.download_button(
            label="Download Task Data (CSV)",
            data=csv,
            file_name=f"asvflow_tasks_{selected_run['run_name']}.csv",
            mime="text/csv",
            use_container_width=False
        )
    else:
        st.info("⏳ Task execution trace not yet available. Trace file is created when pipeline begins executing tasks.")

    # Auto-refresh mechanism
    if auto_refresh:
        time.sleep(refresh_interval)
        st.rerun()


if __name__ == "__main__":
    main()
