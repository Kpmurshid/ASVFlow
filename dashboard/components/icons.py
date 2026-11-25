"""Small inline Lucide icon set shared by dashboard UI components."""

from html import escape
from urllib.parse import quote


_PATHS = {
    "house": '<path d="m3 10 9-7 9 7"/><path d="M5 9v12h14V9"/><path d="M9 21v-8h6v8"/>',
    "microscope": '<path d="M6 18h8"/><path d="M3 22h18"/><path d="M14 22a7 7 0 0 0 7-7"/><path d="M9 14 4 9l3-3 5 5"/><path d="m13 6 3-3 3 3-3 3"/><path d="m10 10 4-4"/>',
    "dna": '<path d="M2 15c6.667 0 6.667-12 13.333-12"/><path d="M2 9c6.667 0 6.667 12 13.333 12"/><path d="M8 12h6"/><path d="M7 6h6"/><path d="M7 18h6"/>',
    "tags": '<path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l7.828 7.828a2 2 0 0 0 2.828 0l7.172-7.172a2 2 0 0 0 0-2.828z"/><circle cx="7.5" cy="7.5" r=".5"/>',
    "chart": '<path d="M3 3v18h18"/><path d="m19 9-5 5-4-4-5 5"/><path d="M15 9h4v4"/>',
    "search": '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>',
    "git-branch": '<path d="M6 3v12"/><circle cx="18" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M18 9a9 9 0 0 1-9 9"/>',
    "refresh": '<path d="M20 7v5h-5"/><path d="M4 17v-5h5"/><path d="M5.64 9A7 7 0 0 1 18.36 7L20 12M4 12l1.64 5a7 7 0 0 0 12.72-2"/>',
    "chart-no-axes-combined": '<path d="M12 3v18"/><path d="M3 12h18"/><path d="m3 7 5 5-5 5"/><path d="m21 7-5 5 5 5"/><path d="M7 3l5 5 5-5"/><path d="m7 21 5-5 5 5"/>',
    "file-chart": '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M8 18v-3M12 18v-6M16 18v-2"/>',
    "check": '<path d="m5 12 4 4L19 6"/>',
    "circle-alert": '<circle cx="12" cy="12" r="10"/><path d="M12 8v4"/><path d="M12 16h.01"/>',
    "circle": '<circle cx="12" cy="12" r="10"/>',
}


def icon_svg(name: str, size: int = 22, color: str = "currentColor") -> str:
    """Return an accessible inline SVG using Lucide's 24px line treatment."""
    paths = _PATHS[name]
    return (f'<svg aria-hidden="true" width="{size}" height="{size}" viewBox="0 0 24 24" '
            f'fill="none" stroke="{escape(color, quote=True)}" stroke-width="1.8" '
            'stroke-linecap="round" stroke-linejoin="round" focusable="false">'
            f'{paths}</svg>')


def icon_data_uri(name: str) -> str:
    """Return a compact SVG data URI for CSS masks on native Streamlit controls."""
    svg = icon_svg(name, 24, "#ffffff")
    return f"url(\"data:image/svg+xml,{quote(svg, safe='')}\")"
