"""QC report explorer for MultiQC and individual FastQC outputs."""

import sys
from pathlib import Path

import streamlit as st
import streamlit.components.v1 as components

sys.path.insert(0, str(Path(__file__).parent.parent))
from components.navigation import render_sidebar_navigation
from components.presentation import render_page_header, section_heading

st.set_page_config(page_title="QC Results", page_icon="🔬", layout="wide")
render_sidebar_navigation()
render_page_header("Quality Control", "Review run-level summaries and inspect read quality sample by sample.", "🔬")

if "scanner" not in st.session_state or st.session_state.scanner is None:
    st.error("No run selected. Please go to the Home page and select a run.")
    st.stop()

scanner = st.session_state.scanner
outputs = scanner.scan_available_outputs()
tab1, tab2 = st.tabs(["📊 MultiQC Reports", "📈 Individual FastQC"])

with tab1:
    section_heading("MultiQC reports", "Aggregated quality summaries for raw and trimmed reads.")
    raw_report = outputs["qc"].get("raw_multiqc")
    trimmed_report = outputs["qc"].get("trimmed_multiqc")
    choices = ["Raw Reads", "Trimmed Reads"]
    report_type = st.radio("Report", choices, horizontal=True, key="multiqc_selector",
                           format_func=lambda x: f"{'●' if (raw_report if x == 'Raw Reads' else trimmed_report) else '○'}  {x}")
    report_path = raw_report if report_type == "Raw Reads" else trimmed_report
    status_col, detail_col = st.columns([1, 3])
    with status_col:
        if report_path:
            st.success("Report available")
        else:
            st.info("Report pending or unavailable")
    with detail_col:
        st.caption(f"Selected report: {report_path.name}" if report_path else f"No {report_type.lower()} MultiQC report was found for this run.")
    if report_path:
        html_content = report_path.read_text(encoding="utf-8")
        components.html(html_content, height=740, scrolling=True)
        st.download_button(f"📥 Download {report_type} MultiQC report", html_content,
                           f"{report_type.split()[0].lower()}_multiqc_report.html", "text/html")

with tab2:
    section_heading("Individual FastQC reports", "Select a read set, then move between sample reports using the file selector.")
    raw_fastqc = sorted(outputs["qc"].get("raw_fastqc", []), key=lambda p: p.name.lower())
    trimmed_fastqc = sorted(outputs["qc"].get("trimmed_fastqc", []), key=lambda p: p.name.lower())
    read_type = st.radio("Read set", ["Raw Reads", "Trimmed Reads"], horizontal=True, key="fastqc_selector")
    reports = raw_fastqc if read_type == "Raw Reads" else trimmed_fastqc
    other_reports = trimmed_fastqc if read_type == "Raw Reads" else raw_fastqc
    c1, c2 = st.columns(2)
    with c1:
        st.metric(f"{read_type} reports", len(reports))
    with c2:
        st.metric("Other read set", len(other_reports))
    if reports:
        selected = st.selectbox("Sample / report", reports, format_func=lambda p: p.name,
                                key=f"{read_type.lower().split()[0]}_fastqc_select")
        st.caption(f"Viewing {selected.name}")
        components.html(selected.read_text(encoding="utf-8"), height=740, scrolling=True)
    else:
        st.info(f"No {read_type.lower()} FastQC reports are available for this run.")
