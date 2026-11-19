#!/usr/bin/env python3
"""Focused checks for ASV sequence identifiers and phylogeny results."""
import sys
import subprocess
import tempfile
import unittest
from pathlib import Path

import pandas as pd
PROJECT_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_DIR / "dashboard"))

from parsers import OutputScanner
from utils.phylogeny import (
    merge_taxonomy_tables, parse_newick, read_fasta, read_sequence_table_ids,
    validate_newick, tree_geometry,
)


class PhylogenyTests(unittest.TestCase):
    def test_extracted_sequences_preserve_sequence_table_identifiers(self):
        table = "ASV_ID\tS1\tS2\nASV_0001\t3\t0\nASV_0002\t0\t9\n"
        fasta = ">ASV_0001\nACGT\n>ASV_0002\nTGCA\n"
        self.assertEqual(list(read_fasta(fasta)), read_sequence_table_ids(table))
        self.assertEqual(read_fasta(fasta), {"ASV_0001": "ACGT", "ASV_0002": "TGCA"})
        tree_leaves = {leaf["name"] for leaf in tree_geometry(parse_newick("(ASV_0001:0.1,ASV_0002:0.1);"))[1]}
        self.assertEqual(tree_leaves, set(read_sequence_table_ids(table)))

    def test_newick_validation_and_tree_leaves(self):
        newick = "(ASV_0001:0.1,(ASV_0002:0.2,ASV_0003:0.3):0.1);"
        self.assertTrue(validate_newick(newick))
        self.assertFalse(validate_newick("(ASV_0001,ASV_0002)"))
        self.assertFalse(validate_newick("(ASV_0001,,ASV_0002);"))
        with tempfile.TemporaryDirectory() as temp_dir:
            tree = Path(temp_dir) / "tree.nwk"
            fasta = Path(temp_dir) / "alignment.fasta"
            tree.write_text(newick)
            fasta.write_text(">ASV_0001\nACGT\n>ASV_0002\nTGCA\n>ASV_0003\nGCTA\n")
            check = ["bash", str(PROJECT_DIR / "bin/validate_newick.sh"), str(tree), str(fasta)]
            self.assertEqual(subprocess.run(check, capture_output=True).returncode, 0)
            tree.write_text("(ASV_0001,,ASV_0002);")
            self.assertNotEqual(subprocess.run(check, capture_output=True).returncode, 0)
            tree.write_text(newick)
            fasta.write_text(">ASV_0001\nACGT\n")
            self.assertNotEqual(subprocess.run(check, capture_output=True).returncode, 0)
        tree = parse_newick(newick)
        _, leaves, _ = tree_geometry(tree)
        self.assertEqual({leaf["name"] for leaf in leaves}, {"ASV_0001", "ASV_0002", "ASV_0003"})
        self.assertEqual({leaf["name"]: leaf["branch_length"] for leaf in leaves}["ASV_0002"], 0.2)
        for layout in ("Rectangular phylogram", "Circular", "Radial"):
            branches, layout_leaves, _ = tree_geometry(parse_newick(newick), layout=layout)
            self.assertEqual(len(layout_leaves), 3)
            self.assertEqual(sorted(branch["length"] for branch in branches), [0.1, 0.1, 0.2, 0.3])

    def test_taxonomy_mapping_and_species_precedence(self):
        genus = pd.DataFrame([
            {"ASV_ID": "ASV_0001", "sequence": "ACGT", "Genus": "Escherichia", "Family": "Enterobacteriaceae"},
            {"ASV_ID": "ASV_0002", "sequence": "TGCA", "Genus": "NA", "Family": "Bacillaceae"},
        ])
        species = pd.DataFrame([
            {"ASV_ID": "ASV_0001", "sequence": "ACGT", "Genus": "Escherichia", "Species": "Escherichia_coli"},
        ])
        result = merge_taxonomy_tables([genus, species])
        self.assertEqual(result["ASV_0001"]["label"], "Escherichia coli")
        self.assertEqual(result["ASV_0001"]["ranks"]["Family"], "Enterobacteriaceae")
        self.assertEqual(result["ASV_0002"]["label"], "Bacillaceae")
        self.assertEqual(result["ASV_0002"]["ranks"]["Genus"], "")
        species["Species"] = "coli"
        result = merge_taxonomy_tables([genus, species])
        self.assertEqual(result["ASV_0001"]["label"], "Escherichia coli")

    def test_layouts_keep_cumulative_branch_distances_and_taxon_groups(self):
        root = parse_newick("(ASV_0001:0.1,(ASV_0002:0.2,ASV_0003:0.3):0.1);")
        taxonomy = {
            "ASV_0001": {"label": "Genus one", "ranks": {"Genus": "Genus one"}},
            "ASV_0002": {"label": "Genus two", "ranks": {"Genus": "Genus two"}},
            "ASV_0003": {"label": "Genus two", "ranks": {"Genus": "Genus two"}},
        }
        expected = {"ASV_0001": 0.1, "ASV_0002": 0.3, "ASV_0003": 0.4}
        layout_angles = {}
        for layout in ("Rectangular phylogram", "Circular", "Radial"):
            branches, leaves, _ = tree_geometry(parse_newick("(ASV_0001:0.1,(ASV_0002:0.2,ASV_0003:0.3):0.1);"), taxonomy, layout=layout)
            for leaf in leaves:
                distance = leaf["x"] if layout == "Rectangular phylogram" else (leaf["x"] ** 2 + leaf["plot_y"] ** 2) ** 0.5
                self.assertAlmostEqual(distance, expected[leaf["name"]])
            self.assertEqual(next(leaf for leaf in leaves if leaf["name"] == "ASV_0002")["color_group"], "Genus two")
            layout_angles[layout] = {leaf["name"]: leaf["angle"] for leaf in leaves}
        self.assertNotEqual(layout_angles["Circular"], layout_angles["Radial"])

    def test_phylogeny_output_availability_and_unavailable_state(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            scanner = OutputScanner(temp_dir, run_info={"status": "OK"})
            self.assertIsNone(scanner.scan_available_outputs()["phylogeny"]["tree"])
            self.assertEqual(scanner.get_artifact_status("phylogeny", "tree"), "Unavailable")
            tree = Path(temp_dir) / "phylogeny/asv_tree.nwk"
            tree.parent.mkdir()
            tree.write_text("(ASV_0001,ASV_0002);\n")
            self.assertEqual(scanner.get_artifact_status("phylogeny", "tree"), "Available")
            self.assertTrue(scanner.get_output_stats()["phylogeny_available"])


if __name__ == "__main__":
    unittest.main()
