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
import streamlit.components.v1 as components

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from parsers import NextflowMonitor, OutputScanner


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
    /* Sidebar global tweaks */
    [data-testid="stSidebar"] {
        padding-top: 1rem;
    }

    /* Brand container - compact and clean */
    [data-testid="stSidebar"] .brand-container {
        text-align: center;
        padding: 0.75rem 0 1rem 0;
        margin-bottom: 1.25rem;
        border-bottom: 1px solid rgba(128, 128, 128, 0.15);
    }
    [data-testid="stSidebar"] .brand-container img {
        margin-bottom: 0.5rem;
    }
    [data-testid="stSidebar"] .brand-title {
        font-size: 1.15rem;
        font-weight: 600;
        margin: 0.5rem 0 0.15rem 0;
        color: #1f2937;
    }
    [data-testid="stSidebar"] .brand-sub {
        font-size: 0.8rem;
        opacity: 0.65;
        margin: 0;
    }

    /* Run selector spacing */
    [data-testid="stSidebar"] .run-selector-spacer {
        margin-bottom: 1.5rem;
    }

    /* Settings section - compact grouping */
    [data-testid="stSidebar"] .settings-container {
        margin-top: 1.5rem;
        padding-top: 1rem;
        border-top: 1px solid rgba(128, 128, 128, 0.15);
    }

    /* Footer - minimal */
    [data-testid="stSidebar"] .footer-container {
        margin-top: 2rem;
        padding-top: 0.75rem;
        border-top: 1px solid rgba(128, 128, 128, 0.1);
        font-size: 0.7rem;
        opacity: 0.5;
        text-align: center;
    }

    /* Streamlit native selectbox styling - reduce spacing */
    [data-testid="stSidebar"] [data-testid="stSelectbox"] {
        margin-bottom: 0;
    }

    /* Streamlit native checkbox styling */
    [data-testid="stSidebar"] [data-testid="stCheckbox"] {
        margin-bottom: 0.5rem;
    }
    </style>
    """, unsafe_allow_html=True)

    # ========== BRAND SECTION ==========
    logo_path = Path(__file__).parent / "public" / "mkp-logo-sm.png"
    brand_html = '<div class="brand-container">'
    if logo_path.exists():
        import base64
        with open(logo_path, "rb") as f:
            logo_b64 = base64.b64encode(f.read()).decode()
        brand_html += f'<img src="data:image/png;base64,{logo_b64}" width="100" />'
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

    # Run selector with label
    selected_idx = st.sidebar.selectbox(
        "Run Selection",
        range(len(run_options)),
        format_func=lambda i: run_options[i],
        index=len(run_options) - 1,
        help="Select a Nextflow run to explore results"
    )

    st.sidebar.markdown('<div class="run-selector-spacer"></div>', unsafe_allow_html=True)

    selected_run = available_runs[selected_idx]
    selected_run_key = f"{selected_run.get('run_name')}:{selected_run.get('session_id')}:{selected_run.get('timestamp')}"
    outdir = monitor.get_run_outdir(selected_run)
    selected_run['artifacts'] = monitor.get_run_artifacts(selected_run, available_runs)
    scanner = OutputScanner(outdir, run_info=selected_run)
    st.session_state.selected_run = selected_run
    st.session_state.scanner = scanner

    # Scan available outputs for dashboard rendering
    outputs = scanner.scan_available_outputs()

    # Note: Streamlit automatically creates navigation from the /pages folder
    # The native navigation appears above and provides full routing functionality

    # ========== SETTINGS SECTION ==========
    st.sidebar.markdown('<div class="settings-container"></div>', unsafe_allow_html=True)

    auto_refresh = st.sidebar.checkbox(
        "Auto-refresh",
        value=(selected_run['status'] in ['-', 'RUNNING']),
        help="Automatically reload dashboard at regular intervals"
    )

    if auto_refresh:
        refresh_interval = st.sidebar.slider(
            "Interval (seconds)",
            min_value=2,
            max_value=30,
            value=5,
            help="Time between automatic refreshes"
        )
        st.sidebar.caption(f"⟳ Refreshing every {refresh_interval}s")

    if st.sidebar.button("🔄 Refresh Now", use_container_width=True, type="secondary"):
        st.rerun()

    # ========== FOOTER ==========
    st.sidebar.markdown(f'''
    <div class="footer-container">
        <div>ASVFlow v2.0.0</div>
        <div>{project_dir.name}</div>
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

    # ========== TASK EXECUTION SUMMARY ==========
    task_summary = scanner.get_task_status_summary()
    st.markdown('<div style="font-size: 1.1rem; font-weight: 600; margin: 0.75rem 0 0.5rem; padding-bottom: 0.4rem; border-bottom: 2px solid rgba(128, 128, 128, 0.1);">Task Execution Summary</div>', unsafe_allow_html=True)

    if task_summary['total'] > 0:
        st.caption("Task statuses from this run's execution trace")
        metric_cols = st.columns(4)
        metrics = (
            ('Executed', task_summary['executed'], '#16a34a'),
            ('Cached', task_summary['cached'], '#7c3aed'),
            ('Failed', task_summary['failed'], '#dc2626' if task_summary['failed'] > 0 else '#6b7280'),
            ('Aborted', task_summary['aborted'], '#6b7280'),
        )
        for col, (label, value, color) in zip(metric_cols, metrics):
            with col:
                st.markdown(
                    f'<div style="display:flex; align-items:center; gap:0.45rem; padding:0.35rem 0.6rem; '
                    f'border:1px solid rgba(128,128,128,0.12); border-radius:6px; background:rgba(128,128,128,0.04);">'
                    f'<span style="font-size:0.8rem; opacity:0.75">{label}</span>'
                    f'<strong style="margin-left:auto; color:{color}; font-size:1rem">{value}</strong></div>',
                    unsafe_allow_html=True,
                )

        completed_total = task_summary['executed'] + task_summary['cached']
        progress = completed_total / task_summary['total']
        st.markdown(
            f'<div style="display:flex; justify-content:space-between; margin:0.55rem 0 0.25rem; font-size:0.78rem; opacity:0.75">'
            f'<span>Overall Progress</span><span>{completed_total} / {task_summary["total"]} tasks</span></div>'
            f'<div role="progressbar" aria-valuenow="{progress * 100:.1f}" aria-valuemin="0" aria-valuemax="100" '
            f'style="height:5px; border-radius:4px; background:rgba(128,128,128,0.16); overflow:hidden">'
            f'<div style="height:100%; width:{min(progress * 100, 100):.1f}%; background:#16a34a; border-radius:4px"></div></div>',
            unsafe_allow_html=True,
        )
    else:
        trace_status = selected_run.get('artifacts', {}).get('trace', {}).get('status', 'Missing')
        trace_messages = {
            'Pending': 'Task metrics are pending while this run is active.',
            'Available': 'The execution trace is available but contains no task rows.',
            'Missing': 'Task metrics are missing for this invocation.',
            'Generation failed': 'Nextflow failed to generate the task trace for this invocation.'
        }
        st.info(trace_messages.get(trace_status, 'Task metrics are missing for this invocation.'))

    with st.expander("View Run Command"):
        st.code(selected_run['command'], language='bash')
    st.caption(f"Output Directory: `{outdir}`")

    # ========== QUICK ACCESS SECTION ==========
    st.markdown('<div style="font-size: 1.1rem; font-weight: 600; margin-bottom: 1rem; margin-top: 2rem; padding-bottom: 0.5rem; border-bottom: 2px solid rgba(128, 128, 128, 0.1);">Quick Access</div>', unsafe_allow_html=True)

    st.caption("Navigate to detailed analysis pages")

    st.markdown("""
    <style>
    [class*="st-key-quick_access_"] button {
        width: 100%;
        min-height: 108px;
        padding: 1rem;
        border-radius: 8px;
        text-align: center;
        white-space: pre-line;
        line-height: 1.65;
        font-weight: 400;
    }
    [class*="st-key-quick_access_"][class*="_available"] button {
        background-color: rgba(34, 197, 94, 0.1);
        border: 1px solid rgba(34, 197, 94, 0.2);
    }
    [class*="st-key-quick_access_"][class*="_pending"] button,
    [class*="st-key-quick_access_"][class*="_optional"] button {
        background-color: rgba(128, 128, 128, 0.05);
        border: 1px solid rgba(128, 128, 128, 0.1);
        opacity: 0.65;
    }
    </style>
    """, unsafe_allow_html=True)

    def quick_access_card(key, title, status, available, page=None, artifact_path=None):
        state = 'available' if available else ('optional' if status == 'Optional' else 'pending')
        icon = '✓' if available else '○'
        clicked = st.button(
            f'{icon}  **{title}**  \n{status}',
            key=f'quick_access_{key}_{state}',
            use_container_width=True
        )
        if clicked:
            if page:
                st.switch_page(str(Path(__file__).parent / 'pages' / page))
            elif artifact_path:
                st.session_state.quick_access_report_path = str(artifact_path)
                st.session_state.quick_access_report_message = None
                st.session_state.quick_access_report_run_key = selected_run_key
            else:
                st.session_state.quick_access_report_path = None
                st.session_state.quick_access_report_message = 'No Nextflow report or timeline is available for this run yet.'
                st.session_state.quick_access_report_run_key = selected_run_key

    col1, col2, col3 = st.columns(3)

    with col1:
        quick_access_card(
            'qc', 'QC Results', 'Available' if outputs['qc']['raw_multiqc'] else 'Pending',
            bool(outputs['qc']['raw_multiqc']), page='1_🔬_QC_Results.py'
        )

    with col2:
        quick_access_card(
            'dada2', 'DADA2 Results', 'Available' if outputs['dada2']['seqtab'] else 'Pending',
            bool(outputs['dada2']['seqtab']), page='2_🧬_DADA2_Results.py'
        )

    with col3:
        quick_access_card(
            'taxonomy', 'Taxonomy', 'Available' if outputs['taxonomy']['taxonomy_table'] else 'Pending',
            bool(outputs['taxonomy']['taxonomy_table']), page='3_🦠_Taxonomy.py'
        )

    st.markdown("")  # Spacing

    # Second row for additional items
    col4, col5, col6 = st.columns(3)

    with col4:
        quick_access_card(
            'community', 'Community Analysis',
            'Available' if outputs['community']['alpha_diversity'] else 'Optional',
            bool(outputs['community']['alpha_diversity']), page='4_📊_Community_Analysis.py'
        )

    with col5:
        report_states = outputs['report_states']
        report_status = report_states['execution_report']
        timeline_status = report_states['execution_timeline']
        reports_available = report_status == 'Available' or timeline_status == 'Available'
        reports_status_text = f"Report: {report_status} · Timeline: {timeline_status}"
        report_path = outputs['reports']['execution_report'] or outputs['reports']['execution_timeline']
        quick_access_card(
            'reports', 'Nextflow Reports', reports_status_text, reports_available,
            artifact_path=report_path
        )

    with col6:
        quick_access_card(
            'sample_explorer', 'Sample Explorer',
            'Available' if outputs['dada2']['seqtab'] else 'Pending',
            bool(outputs['dada2']['seqtab']), page='5_🔍_Sample_Explorer.py'
        )

    st.markdown("")  # Spacing

    report_run_key = st.session_state.get('quick_access_report_run_key')
    report_path = (
        st.session_state.get('quick_access_report_path')
        if report_run_key == selected_run_key else None
    )
    if report_path:
        st.markdown("### Nextflow Report Preview")
        try:
            components.html(Path(report_path).read_text(encoding='utf-8'), height=800, scrolling=True)
        except OSError as error:
            st.warning(f"Unable to open this report artifact: {error}")
    elif report_run_key == selected_run_key and st.session_state.get('quick_access_report_message'):
        st.info(st.session_state.quick_access_report_message)

    # ========== TASK DETAILS SECTION ==========
    st.markdown('<div style="font-size: 1.1rem; font-weight: 600; margin-bottom: 1rem; margin-top: 2rem; padding-bottom: 0.5rem; border-bottom: 2px solid rgba(128, 128, 128, 0.1);">Task Execution Details</div>', unsafe_allow_html=True)

    # Read the selected invocation's execution trace artifact.
    trace_df = scanner.get_execution_trace()

    if not trace_df.empty:
        st.caption(f"Showing {len(trace_df)} tasks from this run's execution trace")

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
        trace_status = selected_run.get('artifacts', {}).get('trace', {}).get('status', 'Missing')
        trace_messages = {
            'Pending': 'Task execution trace is pending while this run is active.',
            'Available': 'Task execution trace is available but contains no task rows.',
            'Missing': 'Task execution trace is missing for this invocation.',
            'Generation failed': 'Nextflow failed to generate the task execution trace for this invocation.'
        }
        st.info(trace_messages.get(trace_status, 'Task execution trace is missing for this invocation.'))

    # Auto-refresh mechanism
    if auto_refresh:
        time.sleep(refresh_interval)
        st.rerun()


if __name__ == "__main__":
    main()
