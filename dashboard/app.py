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
    st.title("🧬 ASVFlow Live Dashboard")
    st.caption("Interactive Pipeline Monitoring and Scientific Results Explorer")

    # Run information banner
    col1, col2, col3 = st.columns([2, 1, 1])

    with col1:
        st.info(f"**Run:** {selected_run['run_name']}")

    with col2:
        status = selected_run['status']
        status_label = {
            'OK': '✅ Completed',
            'ERR': '❌ Failed',
            '-': '⏳ Running',
            'RUNNING': '🔄 Running'
        }.get(status, '❓ Unknown')
        st.info(f"**Status:** {status_label}")

    with col3:
        st.info(f"**Started:** {selected_run['timestamp']}")

    st.divider()

    # Render overview component
    render_overview(monitor, scanner, selected_run)

    # Quick links to results
    st.divider()
    st.subheader("🔗 Quick Access to Results")

    col1, col2, col3 = st.columns(3)

    with col1:
        if outputs['qc']['raw_multiqc']:
            st.success("✅ QC Results Available")
        else:
            st.warning("⏳ QC Results Pending")

    with col2:
        if outputs['dada2']['seqtab']:
            st.success("✅ DADA2 Complete")
        else:
            st.warning("⏳ DADA2 Processing")

    with col3:
        if outputs['taxonomy']['taxonomy_table']:
            st.success("✅ Taxonomy Assigned")
        else:
            st.warning("⏳ Taxonomy Pending")

    col4, col5, col6 = st.columns(3)

    with col4:
        if outputs['community']['alpha_diversity']:
            st.success("✅ Community Analysis")
        else:
            st.info("ℹ️ Community (Optional)")

    with col5:
        if outputs['reports']['execution_report']:
            st.success("✅ Nextflow Reports")
        else:
            st.info("ℹ️ Reports Pending")

    with col6:
        if outputs['dada2']['seqtab']:
            st.success("✅ Sample Explorer")
        else:
            st.info("ℹ️ Sample Explorer")

    # Task details table
    st.divider()
    st.subheader("📋 Completed Task Details")

    trace_df = scanner.get_execution_trace()

    if not trace_df.empty:
        st.caption(f"Showing {len(trace_df)} completed tasks from execution trace")

        # Display key columns
        display_cols = ['name', 'status', 'exit', 'duration', 'realtime', '%cpu', 'peak_rss']
        available_cols = [col for col in display_cols if col in trace_df.columns]

        if available_cols:
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
            label="📥 Download Task Data (CSV)",
            data=csv,
            file_name=f"asvflow_tasks_{selected_run['run_name']}.csv",
            mime="text/csv"
        )
    else:
        st.info("Task execution trace not yet available. Trace file is created when pipeline begins executing tasks.")

    # Auto-refresh mechanism
    if auto_refresh:
        time.sleep(refresh_interval)
        st.rerun()


if __name__ == "__main__":
    main()
