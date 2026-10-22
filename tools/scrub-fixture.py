#!/usr/bin/env python3
"""Copy a bellhop-probe output into Tests/Fixtures with personal content replaced.

Menus can hold private data: clipboard history (CopyClip), chat titles (ChatGPT), file counts in tooltips.
The structure, frames, roles and shortcuts stay intact so tests still exercise real shapes.

    python3 -I tools/scrub-fixture.py probe-output/latest.json Tests/Fixtures/macos27-laptop-overflow.json
"""
import json
import re
import sys

# Bundle ID → how to scrub its menu. "all-but-chrome" keeps fixed app commands (Quit, Preferences…) and renames the rest.
RULES = {
    "com.fiplab.clipboard": "all-but-chrome",
    "com.openai.codex": "all-but-chrome",
    "com.openai.chat": "all-but-chrome",
}
CHROME = re.compile(
    r"^(Quit.*|Preferences.*|Settings.*|Delete All History|Customer Support|Join Mailing List|Rate App|"
    r"Computer Use|No Active Sessions|Pinned|Select the clip.*|Open .*|Check for Updates.*)$"
)
SECRETLIKE = re.compile(r"(https?://|@|[A-Za-z0-9_]{24,})")


def scrub_nodes(nodes, counter):
    for node in nodes:
        title = node.get("title")
        if title and not node.get("isSeparator") and not CHROME.match(title):
            counter[0] += 1
            node["title"] = f"Item {counter[0]}"
        scrub_nodes(node.get("children") or [], counter)


def main(source, destination):
    data = json.load(open(source))
    data.pop("accessibilityHost", None)
    for app in data["apps"]:
        for item in app["items"]:
            if item.get("help"):
                item["help"] = item["help"].split("\n")[0]
            if RULES.get(app.get("bundleID")) == "all-but-chrome":
                scrub_nodes(item["menu"]["items"], [0])

    leftovers = []

    def check(nodes, app):
        for node in nodes:
            if node.get("title") and SECRETLIKE.search(node["title"]):
                leftovers.append(f'{app}: {node["title"]}')
            check(node.get("children") or [], app)

    for app in data["apps"]:
        for item in app["items"]:
            check(item["menu"]["items"], app["name"])
    if leftovers:
        sys.exit("Possible private titles left; add a rule:\n  " + "\n  ".join(leftovers))

    with open(destination, "w") as out:
        json.dump(data, out, indent=2, sort_keys=True, ensure_ascii=False)
        out.write("\n")
    print(f"wrote {destination}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
