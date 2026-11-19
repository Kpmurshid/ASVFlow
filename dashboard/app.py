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
from html import escape
import streamlit.components.v1 as components

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from parsers import NextflowMonitor, OutputScanner
from components.navigation import render_sidebar_navigation
from components.theme import render_home_header


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

    # Shared sidebar brand and legacy multipage navigation.
    render_sidebar_navigation()

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
    <div class="asv-sidebar-footer">
        <div>ASVFlow v2.0.0</div>
        <div>{project_dir.name}</div>
    </div>
    ''', unsafe_allow_html=True)

    # Main content area - Home/Overview
    # ========== HEADER SECTION ==========
    render_home_header()

    # Run information banner - Compact cards
    col1, col2, col3 = st.columns([1.4, 1, 1])

    with col1:
        st.markdown(f"""
        <div class="asv-overview-card"><div class="asv-overview-label">ACTIVE RUN</div>
        <div class="asv-overview-value">{escape(str(selected_run['run_name']))}</div>
        <div style="font: .72rem ui-monospace,monospace;color:#718697;margin-top:.25rem">{escape(str(selected_run.get('session_id', '')))}</div></div>
        """, unsafe_allow_html=True)

    with col2:
        status = selected_run['status']
        status_colors = {
            'OK': ('#13866e', 'Completed'),
            'ERR': ('#c43d4b', 'Failed'),
            '-': ('#1688b8', 'Running'),
            'RUNNING': ('#1688b8', 'Running')
        }
        color, label = status_colors.get(status, ('#718096', 'Unknown'))

        st.markdown(f"""
        <div class="asv-overview-card" style="border-top-color:{color}"><div class="asv-overview-label">STATUS</div>
        <div class="asv-overview-value" style="color:{color}">{label}</div></div>
        """, unsafe_allow_html=True)

    with col3:
        st.markdown(f"""
        <div class="asv-overview-card" style="border-top-color:#718da2"><div class="asv-overview-label">STARTED</div>
        <div class="asv-overview-value">{escape(str(selected_run['timestamp']))}</div></div>
        """, unsafe_allow_html=True)

    st.markdown("")  # Spacing
    st.markdown("")  # Spacing

    # ========== TASK EXECUTION SUMMARY ==========
    task_summary = scanner.get_task_status_summary()
    st.markdown('<div class="asv-section">Task Execution Summary</div>', unsafe_allow_html=True)

    if task_summary['total'] > 0:
        st.caption("Task statuses from this run's execution trace")
        metric_cols = st.columns(4)
        metrics = (
            ('✓', 'Executed', task_summary['executed'], '#13866e'),
            ('↻', 'Cached', task_summary['cached'], '#7456b8'),
            ('!', 'Failed', task_summary['failed'], '#c43d4b' if task_summary['failed'] > 0 else '#8292a0'),
            ('○', 'Aborted', task_summary['aborted'], '#8292a0'),
        )
        for col, (icon, label, value, color) in zip(metric_cols, metrics):
            with col:
                st.markdown(
                    f'<div class="asv-metric-card" style="--metric-accent:{color}">'
                    f'<div class="asv-metric-label">{icon} &nbsp;{label}</div>'
                    f'<div class="asv-metric-value">{value}</div></div>',
                    unsafe_allow_html=True,
                )

        completed_total = task_summary['executed'] + task_summary['cached']
        progress = completed_total / task_summary['total']
        progress_color = {
            'OK': '#13866e', 'ERR': '#c43d4b', '-': '#1688b8', 'RUNNING': '#1688b8'
        }.get(selected_run['status'], '#8292a0')
        st.markdown(
            f'<div style="display:flex;justify-content:space-between;margin:.8rem 0 .35rem;color:#64798c;font-size:.82rem">'
            f'<span><strong style="color:#17324d">Overall Pipeline Progress</strong></span>'
            f'<span>{completed_total} / {task_summary["total"]} tasks &nbsp;·&nbsp; {progress*100:.0f}%</span></div>'
            f'<div class="asv-progress-track" role="progressbar" aria-valuenow="{progress * 100:.1f}" aria-valuemin="0" aria-valuemax="100">'
            f'<div class="asv-progress-fill" style="width:{min(progress * 100, 100):.1f}%;background:{progress_color}"></div></div>',
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
    st.markdown(f'<div style="margin:.55rem 0 1rem;color:#64798c;font-size:.82rem">Output Directory</div><div style="font: .82rem ui-monospace,monospace;overflow-wrap:anywhere;background:#edf4f7;padding:.8rem 1rem;border-radius:8px;color:#29465d">{escape(str(outdir))}</div>', unsafe_allow_html=True)

    # ========== QUICK ACCESS SECTION ==========
    st.markdown('<div class="asv-section">Quick Access</div>', unsafe_allow_html=True)

    st.caption("Navigate to detailed analysis pages")

    def quick_access_card(key, title, description, icon, status, available, page=None, artifact_path=None):
        state = 'available' if available else ('optional' if status == 'Optional' else 'pending')
        indicator = '● Available' if available else ('◌ Optional' if status == 'Optional' else '◷ Pending')
        clicked = st.button(
            f'{icon}  **{title}**  \n{description}  \n\n{indicator}',
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
            'qc', 'QC Results', 'Read QC and quality metrics', '🔬', 'Available' if outputs['qc']['raw_multiqc'] else 'Pending',
            bool(outputs['qc']['raw_multiqc']), page='1_🔬_QC_Results.py'
        )

    with col2:
        quick_access_card(
            'dada2', 'DADA2 Results', 'ASV inference, filtering and denoising', '🧬', 'Available' if outputs['dada2']['seqtab'] else 'Pending',
            bool(outputs['dada2']['seqtab']), page='2_🧬_DADA2_Results.py'
        )

    with col3:
        quick_access_card(
            'taxonomy', 'Taxonomy', 'Taxonomic assignment and abundance', '🦠', 'Available' if outputs['taxonomy']['taxonomy_table'] else 'Pending',
            bool(outputs['taxonomy']['taxonomy_table']), page='3_🦠_Taxonomy.py'
        )

    st.markdown("")  # Spacing

    # Second row for additional items
    col4, col5, col6 = st.columns(3)

    with col4:
        quick_access_card(
            'community', 'Community Analysis', 'Diversity and community composition', '📊',
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
            'reports', 'Nextflow Reports', 'Execution report and timeline', '📈', reports_status_text, reports_available,
            artifact_path=report_path
        )

    with col6:
        quick_access_card(
            'sample_explorer', 'Sample Explorer', 'Explore samples, ASVs and taxonomy', '🔎',
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
            table = trace_df[available_cols]
            def style_task_row(row):
                shade = '#ffffff' if row.name % 2 == 0 else '#f3f8fb'
                styles = [f'background-color: {shade}' for _ in row]
                if 'status' in row.index:
                    status_style = {
                        'COMPLETED': 'color:#13795b;font-weight:700',
                        'CACHED': 'color:#7251a8;font-weight:700',
                        'FAILED': 'color:#bf3345;font-weight:700',
                        'ABORTED': 'color:#697b89;font-weight:700',
                        'RUNNING': 'color:#147fb0;font-weight:700',
                    }.get(str(row['status']).upper(), 'color:#63798a')
                    styles[table.columns.get_loc('status')] += ';' + status_style
                return styles

            st.dataframe(
                table.style.apply(style_task_row, axis=1),
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
