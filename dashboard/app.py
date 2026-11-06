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

    # Sidebar: Logo at top (before title)
    logo_path = Path(__file__).parent / "public" / "mkp-logo-sm.png"
    if logo_path.exists():
        st.sidebar.image(str(logo_path), width=100)

    # Sidebar: Branding
    st.sidebar.title("ASVFlow Live")
    st.sidebar.caption("🧬 Interactive Results Explorer")
    st.sidebar.caption("**Phase 2:** Scientific Visualization")

    # List available runs
    available_runs = monitor.list_runs()

    if not available_runs:
        st.sidebar.warning("No Nextflow runs found")
        st.warning("No ASVFlow runs detected in this directory.")
        st.info("Run ASVFlow with `nextflow run main.nf ...` to begin monitoring.")
        return

    # Format run options for selectbox
    run_options = []
    for run in available_runs:
        status_icon = {
            'OK': '✅',
            'ERR': '❌',
            '-': '⏳'
        }.get(run['status'], '❓')

        label = f"{status_icon} {run['run_name']} ({run['timestamp']})"
        run_options.append(label)

    # Select run (default to most recent)
    selected_idx = st.sidebar.selectbox(
        "Select Run",
        range(len(run_options)),
        format_func=lambda i: run_options[i],
        index=len(run_options) - 1  # Most recent
    )

    selected_run = available_runs[selected_idx]

    # Get output directory for this run
    outdir = monitor.get_run_outdir(selected_run)
    scanner = OutputScanner(outdir)

    # Store in session state for access by other pages
    st.session_state.selected_run = selected_run
    st.session_state.scanner = scanner

    st.sidebar.divider()

    # Navigation hints
    st.sidebar.subheader("📑 Available Pages")
    outputs = scanner.scan_available_outputs()

    pages_status = [
        ("🏠 Overview", True),
        ("🔬 QC Results", any(outputs['qc'].values())),
        ("🧬 DADA2 Results", any(outputs['dada2'].values())),
        ("🦠 Taxonomy", any(outputs['taxonomy'].values())),
        ("📊 Community Analysis", any(outputs['community'].values())),
        ("🔍 Sample Explorer", any(outputs['dada2'].values())),
    ]

    for page_name, available in pages_status:
        if available:
            if page_name == "🏠 Overview":
                st.sidebar.info(f"▶️ {page_name}")
            else:
                st.sidebar.success(f"✅ {page_name}")
        else:
            st.sidebar.caption(f"⚪ {page_name} (not available)")

    st.sidebar.caption("*Use sidebar to navigate*")

    st.sidebar.divider()

    # Auto-refresh control
    auto_refresh = st.sidebar.checkbox(
        "Auto-refresh",
        value=(selected_run['status'] in ['-', 'RUNNING']),
        help="Periodically reload run metadata and completed task data"
    )

    if auto_refresh:
        refresh_interval = st.sidebar.slider(
            "Refresh interval (seconds)",
            min_value=2,
            max_value=30,
            value=5
        )
        st.sidebar.info(f"Refreshing every {refresh_interval}s")

    st.sidebar.divider()

    # Manual refresh button
    if st.sidebar.button("🔄 Refresh Now"):
        st.rerun()

    # Dashboard info
    st.sidebar.caption("---")
    st.sidebar.caption("**ASVFlow Live Dashboard**")
    st.sidebar.caption("Version: 2.0.0 (Phase 2)")
    st.sidebar.caption(f"Project: `{project_dir.name}`")

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
