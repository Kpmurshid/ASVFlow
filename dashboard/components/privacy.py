"""Helpers for keeping local filesystem paths out of dashboard output."""

from pathlib import Path


def display_path(path, project_dir):
    """Return a project-relative path, or only the basename for external paths."""
    resolved = Path(path).expanduser().resolve()
    project_root = Path(project_dir).expanduser().resolve()
    try:
        return resolved.relative_to(project_root).as_posix()
    except ValueError:
        return resolved.name


def sanitize_local_paths(content, project_dir):
    """Replace the local project root in dashboard text with a relative root."""
    project_root = str(Path(project_dir).expanduser().resolve())
    return content.replace(project_root, ".")
