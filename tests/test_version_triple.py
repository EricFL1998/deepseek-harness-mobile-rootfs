#!/usr/bin/env python3
"""Behaviour of the version-triple comparison used by the build workflow.

A rebuild is warranted when the DSH engine or the bundled bridge plugin moved.
The rootfs number is bookkeeping and must NOT drive the decision, or every image
would look like a change and rebuild forever.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

from version_triple import triple  # noqa: E402


class VersionTripleTest(unittest.TestCase):
    def test_reads_both_segments(self):
        self.assertEqual(triple("1.0.0-dsh0.2.1-rc.2-bridge1.1.0"), "0.2.1-rc.2|1.1.0")

    def test_missing_bridge_segment_is_empty(self):
        self.assertEqual(triple("1.0.0-dsh0.2.1-rc.2"), "0.2.1-rc.2|")

    def test_bare_rootfs_version_has_no_engine(self):
        self.assertEqual(triple("1.0.0"), "|")

    def test_rc_and_prerelease_dsh_versions_survive(self):
        self.assertEqual(triple("2.1.3-dsh0.3.0-rc.1-bridge2.0.0"), "0.3.0-rc.1|2.0.0")

    def test_rootfs_number_alone_does_not_change_the_triple(self):
        # The whole point: a rebuilt image with the same dsh+bridge compares equal.
        self.assertEqual(
            triple("1.0.0-dsh0.2.1-rc.2-bridge1.1.0"),
            triple("1.7.4-dsh0.2.1-rc.2-bridge1.1.0"),
        )

    def test_a_bridge_bump_changes_the_triple(self):
        self.assertNotEqual(
            triple("1.0.0-dsh0.2.1-rc.2-bridge1.0.0"),
            triple("1.0.0-dsh0.2.1-rc.2-bridge1.1.0"),
        )

    def test_a_dsh_bump_changes_the_triple(self):
        self.assertNotEqual(
            triple("1.0.0-dsh0.2.1-rc.1-bridge1.1.0"),
            triple("1.0.0-dsh0.2.1-rc.2-bridge1.1.0"),
        )

    def test_a_legacy_image_never_equals_a_bridge_tagged_one(self):
        # Forces one rebuild when the format gains its bridge segment, so no image
        # is left claiming an unknown plugin version.
        self.assertNotEqual(
            triple("1.0.0-dsh0.2.1-rc.2"),
            triple("1.0.0-dsh0.2.1-rc.2-bridge1.1.0"),
        )


if __name__ == "__main__":
    unittest.main()
