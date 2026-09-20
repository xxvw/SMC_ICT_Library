"""Regression cases for local Markdown link validation."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.check_docs import anchors, check_file, links


class DocumentationLinksTest(unittest.TestCase):
    def test_examples_are_not_links(self):
        source = """[real](README.md)
```markdown
[placeholder](missing.md)
```
~~~
[example](another.md)
~~~~
`[inline](unknown.md)`
<!-- [comment](fake.md) -->
"""
        self.assertEqual(links(source), [(1, "README.md")])

    def test_indented_list_links_are_checked(self):
        self.assertEqual(links("- Topic\n    - [child](child.md)\n"), [(2, "child.md")])

    def test_destinations_references_images_and_titles(self):
        source = """[file](docs/example(one).md "Title")
![image](<images/image one.png>)
[label][guide]
[guide]: docs/guide.md
[missing][undefined]
"""
        self.assertCountEqual(links(source), [
            (1, "docs/example(one).md"), (2, "images/image one.png"),
            (4, "docs/guide.md"), (5, "missing-reference:undefined"),
        ])

    def test_github_heading_anchors(self):
        source = """# API `GetSnapshot()`
## 日跨ぎ・セッション
## Duplicate
## Duplicate
Setext title
------------
<a id="manual"></a>
```
# Not a heading
```
"""
        self.assertEqual(anchors(source), {
            "api-getsnapshot", "日跨ぎセッション", "duplicate", "duplicate-1", "setext-title", "manual",
        })

    def test_missing_targets_anchors_and_external_links(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "other file.md").write_text("# A heading\n", encoding="utf-8")
            document = root / "README.md"
            document.write_text("""# Start
[valid](other%20file.md#a-heading)
[local](#start)
[external](https://example.org/missing)
[email](mailto:test@example.org)
[missing](absent.md)
[anchor](other%20file.md#absent)
[escape](../outside.md)
""", encoding="utf-8")
            failures = check_file(document, root)
            self.assertEqual(len(failures), 3)
            self.assertIn("README.md:6: missing local target", failures[0])
            self.assertIn("README.md:7: missing heading anchor", failures[1])
            self.assertIn("README.md:8: link escapes", failures[2])


if __name__ == "__main__":
    unittest.main()
