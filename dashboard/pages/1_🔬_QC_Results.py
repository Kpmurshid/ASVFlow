"""
QC Results Page - ASVFlow Live Dashboard Phase 2

Display FastQC and MultiQC quality control reports.
"""

import streamlit as st
import streamlit.components.v1 as components
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from parsers import OutputScanner

st.set_page_config(page_title="QC Results", page_icon="🔬", layout="wide")

st.title("🔬 Quality Control Results")

# Check session state
if 'scanner' not in st.session_state or st.session_state.scanner is None:
    st.error("No run selected. Please go to the Home page and select a run.")
    st.stop()

scanner = st.session_state.scanner
outputs = scanner.scan_available_outputs()

# QC Results tabs
tab1, tab2 = st.tabs(["📊 MultiQC Reports", "📈 Individual FastQC"])

with tab1:
    st.subheader("MultiQC Aggregated Reports")

    # Horizontal selector for report type
    report_type = st.radio(
        "Select report type:",
        options=["Raw Reads", "Trimmed Reads"],
        horizontal=True,
        key="multiqc_selector"
    )

    # Display selected report at full width
    if report_type == "Raw Reads":
        if outputs['qc']['raw_multiqc']:
            report_path = outputs['qc']['raw_multiqc']
            st.success(f"✅ Report available: `{report_path.name}`")

            # Read HTML content
            with open(report_path, 'r', encoding='utf-8') as f:
                html_content = f.read()

            # Display in iframe at full width
            components.html(html_content, height=800, scrolling=True)

            # Download button
            st.download_button(
                label="📥 Download Raw MultiQC Report",
                data=html_content,
                file_name="raw_multiqc_report.html",
                mime="text/html"
            )
        else:
            st.warning("⏳ Raw reads MultiQC report not yet available")
    
    else:  # Trimmed Reads
        if outputs['qc']['trimmed_multiqc']:
            report_path = outputs['qc']['trimmed_multiqc']
            st.success(f"✅ Report available: `{report_path.name}`")

            with open(report_path, 'r', encoding='utf-8') as f:
                html_content = f.read()

            components.html(html_content, height=800, scrolling=True)

            st.download_button(
                label="📥 Download Trimmed MultiQC Report",
                data=html_content,
                file_name="trimmed_multiqc_report.html",
                mime="text/html"
            )
        else:
            st.warning("⏳ Trimmed reads MultiQC report not yet available")

with tab2:
    st.subheader("Individual Sample FastQC Reports")

    raw_fastqc = outputs['qc']['raw_fastqc']
    trimmed_fastqc = outputs['qc']['trimmed_fastqc']

    if raw_fastqc or trimmed_fastqc:
        # Horizontal selector for read type
        read_type = st.radio(
            "Select read type:",
            options=["Raw Reads", "Trimmed Reads"],
            horizontal=True,
            key="fastqc_selector"
        )

        # Display selected FastQC reports at full width
        if read_type == "Raw Reads":
            if raw_fastqc:
                st.caption(f"{len(raw_fastqc)} FastQC reports available")

                selected_raw = st.selectbox(
                    "Select raw FastQC report",
                    raw_fastqc,
                    format_func=lambda x: x.name,
                    key="raw_fastqc_select"
                )

                if selected_raw:
                    with open(selected_raw, 'r', encoding='utf-8') as f:
                        html_content = f.read()

                    components.html(html_content, height=800, scrolling=True)
            else:
                st.info("No raw FastQC reports found")
        
        else:  # Trimmed Reads
            if trimmed_fastqc:
                st.caption(f"{len(trimmed_fastqc)} FastQC reports available")

                selected_trimmed = st.selectbox(
                    "Select trimmed FastQC report",
                    trimmed_fastqc,
                    format_func=lambda x: x.name,
                    key="trimmed_fastqc_select"
                )

                if selected_trimmed:
                    with open(selected_trimmed, 'r', encoding='utf-8') as f:
                        html_content = f.read()

                    components.html(html_content, height=800, scrolling=True)
            else:
                st.info("No trimmed FastQC reports found")
    else:
        st.info("No FastQC reports available yet")

st.divider()
st.caption("💡 **Tip:** Use MultiQC reports for a quick overview across all samples, then dive into individual FastQC reports for detailed per-sample analysis.")
