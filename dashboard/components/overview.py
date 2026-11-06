"""
Overview Component - Run Status and Progress
"""

import streamlit as st
import plotly.graph_objects as go
from typing import Dict


def render(monitor, scanner, run_info: Dict):
    """Render overview page with run status and progress"""

    st.title("🧬 ASVFlow Live Dashboard")

    if not run_info:
        st.warning("No run selected or no runs available")
        return

    # Run metadata header
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric("Run Name", run_info['run_name'])

    with col2:
        status = run_info['status']
        status_icon = {
            'OK': '✅',
            'ERR': '❌',
            '-': '⏳',
            'RUNNING': '▶️'
        }.get(status, '❓')
        st.metric("Status", f"{status_icon} {status}")

    with col3:
        duration = run_info['duration']
        if duration == '-':
            duration = 'Running...'
        st.metric("Duration", duration)

    with col4:
        session_short = run_info['session_id'][:8]
        st.metric("Session", session_short)

    st.divider()

    # Task status summary
    st.subheader("📊 Completed Task Status")

    task_summary = scanner.get_task_status_summary()

    # Note about monitoring limitations
    if task_summary['total'] > 0:
        st.caption("ℹ️ Showing completed tasks only. Tasks appear after completion, not during execution.")

    col1, col2, col3 = st.columns(3)

    with col1:
        st.metric(
            "✅ Completed",
            task_summary['completed'],
            delta=None,
            delta_color="off"
        )

    with col2:
        st.metric(
            "💾 Cached",
            task_summary['cached'],
            delta=None,
            delta_color="off"
        )

    with col3:
        st.metric(
            "❌ Failed",
            task_summary['failed'],
            delta=None,
            delta_color="inverse" if task_summary['failed'] > 0 else "off"
        )

    # Progress bar
    if task_summary['total'] > 0:
        completed_total = task_summary['completed'] + task_summary['cached']
        progress = completed_total / task_summary['total']
        st.progress(progress)
        st.caption(f"{completed_total} / {task_summary['total']} tasks completed")
    else:
        st.info("No tasks recorded yet. Run may be starting or trace file not generated.")

    st.divider()

    # Output availability
    st.subheader("📁 Available Outputs")

    output_stats = scanner.get_output_stats()

    col1, col2 = st.columns(2)

    with col1:
        if output_stats['qc_available']:
            st.success("✓ QC Reports")
        else:
            st.info("○ QC Reports (not yet available)")

        if output_stats['dada2_available']:
            st.success("✓ DADA2 Results")
        else:
            st.info("○ DADA2 Results (not yet available)")

    with col2:
        if output_stats['taxonomy_available']:
            st.success("✓ Taxonomy Assignment")
        else:
            st.info("○ Taxonomy (optional, not run)")

        if output_stats['community_available']:
            st.success("✓ Community Analysis")
        else:
            st.info("○ Community Analysis (optional, not run)")

    st.divider()

    # Run command
    with st.expander("🔧 Run Command", expanded=False):
        st.code(run_info['command'], language='bash')

    # Output directory
    outdir = monitor.get_run_outdir(run_info)
    st.info(f"**Output Directory:** `{outdir}`")
