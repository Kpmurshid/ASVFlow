"""
Overview Component - Run Status and Progress
Modern, polished scientific bioinformatics dashboard design
"""

import streamlit as st
import plotly.graph_objects as go
from typing import Dict


def _render_custom_css():
    """Inject custom CSS for modern, polished appearance"""
    st.markdown("""
    <style>
    /* Card styling with subtle borders and rounded corners */
    .stMetric {
        background-color: rgba(128, 128, 128, 0.05);
        border: 1px solid rgba(128, 128, 128, 0.1);
        border-radius: 8px;
        padding: 1rem;
    }

    /* Status badge styling */
    .status-badge {
        display: inline-block;
        padding: 0.25rem 0.75rem;
        border-radius: 12px;
        font-size: 0.875rem;
        font-weight: 500;
    }

    .status-completed {
        background-color: rgba(34, 197, 94, 0.15);
        color: #16a34a;
    }

    .status-running {
        background-color: rgba(59, 130, 246, 0.15);
        color: #2563eb;
    }

    .status-failed {
        background-color: rgba(239, 68, 68, 0.15);
        color: #dc2626;
    }

    /* Task metric cards */
    .task-card {
        background-color: rgba(128, 128, 128, 0.05);
        border: 1px solid rgba(128, 128, 128, 0.1);
        border-radius: 8px;
        padding: 1.25rem;
        text-align: center;
        min-height: 100px;
        display: flex;
        flex-direction: column;
        justify-content: center;
    }

    .task-card-value {
        font-size: 2rem;
        font-weight: 600;
        margin: 0.5rem 0;
    }

    .task-card-label {
        font-size: 0.875rem;
        opacity: 0.7;
        margin: 0;
    }

    /* Output status cards */
    .output-card {
        background-color: rgba(128, 128, 128, 0.05);
        border: 1px solid rgba(128, 128, 128, 0.1);
        border-radius: 6px;
        padding: 0.875rem 1rem;
        margin-bottom: 0.5rem;
        display: flex;
        align-items: center;
        gap: 0.75rem;
    }

    .output-available {
        border-left: 3px solid #16a34a;
    }

    .output-pending {
        border-left: 3px solid rgba(128, 128, 128, 0.3);
        opacity: 0.7;
    }

    /* Section header */
    .section-header {
        font-size: 1.1rem;
        font-weight: 600;
        margin-bottom: 1rem;
        margin-top: 2rem;
        padding-bottom: 0.5rem;
        border-bottom: 2px solid rgba(128, 128, 128, 0.1);
    }

    /* Progress label */
    .progress-label {
        display: flex;
        justify-content: space-between;
        margin-bottom: 0.5rem;
        font-size: 0.875rem;
    }
    </style>
    """, unsafe_allow_html=True)


def _render_status_badge(status: str) -> str:
    """Generate HTML for status badge"""
    status_config = {
        'OK': ('Completed', 'status-completed'),
        'ERR': ('Failed', 'status-failed'),
        '-': ('Running', 'status-running'),
        'RUNNING': ('Running', 'status-running')
    }
    label, css_class = status_config.get(status, ('Unknown', 'status-running'))
    return f'<span class="status-badge {css_class}">{label}</span>'


def render(monitor, scanner, run_info: Dict):
    """Render overview page with run status and progress"""

    # Apply custom CSS
    _render_custom_css()

    if not run_info:
        st.warning("No run selected or no runs available")
        return

    # ========== RUN SUMMARY SECTION ==========
    col1, col2, col3, col4 = st.columns([3, 2, 2, 2])

    with col1:
        st.markdown("**Run Name**")
        st.markdown(f"<code>{run_info['run_name']}</code>", unsafe_allow_html=True)

    with col2:
        st.markdown("**Status**")
        status = run_info['status']
        st.markdown(_render_status_badge(status), unsafe_allow_html=True)

    with col3:
        st.markdown("**Duration**")
        duration = run_info['duration']
        if duration == '-':
            duration = 'In progress'
        st.markdown(f"{duration}")

    with col4:
        st.markdown("**Session**")
        session_short = run_info['session_id'][:8]
        st.markdown(f"`{session_short}`")

    st.markdown("")  # Spacing

    # ========== TASK METRICS SECTION ==========
    st.markdown('<div class="section-header">Task Execution Summary</div>', unsafe_allow_html=True)

    # Get session-specific task statistics
    task_summary = scanner.get_task_status_summary(run_info['session_id'], monitor)

    if task_summary['total'] > 0:
        st.caption("Showing completed tasks from execution trace")

        # Task metric cards
        col1, col2, col3, col4 = st.columns(4)

        with col1:
            st.markdown(f"""
            <div class="task-card">
                <div class="task-card-label">Completed</div>
                <div class="task-card-value" style="color: #16a34a;">{task_summary['completed']}</div>
            </div>
            """, unsafe_allow_html=True)

        with col2:
            st.markdown(f"""
            <div class="task-card">
                <div class="task-card-label">Cached</div>
                <div class="task-card-value" style="color: #7c3aed;">{task_summary['cached']}</div>
            </div>
            """, unsafe_allow_html=True)

        with col3:
            failed_color = "#dc2626" if task_summary['failed'] > 0 else "#6b7280"
            st.markdown(f"""
            <div class="task-card">
                <div class="task-card-label">Failed</div>
                <div class="task-card-value" style="color: {failed_color};">{task_summary['failed']}</div>
            </div>
            """, unsafe_allow_html=True)

        with col4:
            st.markdown(f"""
            <div class="task-card">
                <div class="task-card-label">Aborted</div>
                <div class="task-card-value" style="color: #6b7280;">{task_summary['aborted']}</div>
            </div>
            """, unsafe_allow_html=True)

        # Progress indicator
        st.markdown("")  # Spacing
        completed_total = task_summary['completed'] + task_summary['cached']
        progress = completed_total / task_summary['total']

        st.markdown(f"""
        <div class="progress-label">
            <span>Overall Progress</span>
            <span><strong>{completed_total}</strong> / {task_summary['total']} tasks</span>
        </div>
        """, unsafe_allow_html=True)

        st.progress(progress)
    else:
        st.info("⏳ Waiting for pipeline tasks to complete. Task metrics will appear here once execution begins.")

    st.markdown("")  # Spacing

    # ========== AVAILABLE OUTPUTS SECTION ==========
    st.markdown('<div class="section-header">Available Outputs</div>', unsafe_allow_html=True)

    output_stats = scanner.get_output_stats()

    col1, col2 = st.columns(2)

    with col1:
        # QC Reports
        if output_stats['qc_available']:
            st.markdown("""
            <div class="output-card output-available">
                <div>✓</div>
                <div style="flex: 1;"><strong>QC Reports</strong></div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown("""
            <div class="output-card output-pending">
                <div>○</div>
                <div style="flex: 1;">QC Reports</div>
            </div>
            """, unsafe_allow_html=True)

        # DADA2 Results
        if output_stats['dada2_available']:
            st.markdown("""
            <div class="output-card output-available">
                <div>✓</div>
                <div style="flex: 1;"><strong>DADA2 Results</strong></div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown("""
            <div class="output-card output-pending">
                <div>○</div>
                <div style="flex: 1;">DADA2 Results</div>
            </div>
            """, unsafe_allow_html=True)

    with col2:
        # Taxonomy Assignment
        if output_stats['taxonomy_available']:
            st.markdown("""
            <div class="output-card output-available">
                <div>✓</div>
                <div style="flex: 1;"><strong>Taxonomy Assignment</strong></div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown("""
            <div class="output-card output-pending">
                <div>○</div>
                <div style="flex: 1;">Taxonomy Assignment</div>
            </div>
            """, unsafe_allow_html=True)

        # Community Analysis
        if output_stats['community_available']:
            st.markdown("""
            <div class="output-card output-available">
                <div>✓</div>
                <div style="flex: 1;"><strong>Community Analysis</strong></div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown("""
            <div class="output-card output-pending">
                <div>○</div>
                <div style="flex: 1;">Community Analysis <em>(optional)</em></div>
            </div>
            """, unsafe_allow_html=True)

    st.markdown("")  # Spacing

    # ========== ADDITIONAL INFORMATION ==========
    # Run command
    with st.expander("View Run Command"):
        st.code(run_info['command'], language='bash')

    # Output directory
    outdir = monitor.get_run_outdir(run_info)
    st.caption(f"Output Directory: `{outdir}`")
