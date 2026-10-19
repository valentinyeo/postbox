#!/usr/bin/env python3
import re
import sys

SKIN_TONES = {0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF}

ALIASES = {
    "\U0001F602": "laugh lol haha",
    "\U0001F923": "lol",
    "\U0001F604": "happy smile",
    "\U0001F60A": "happy smile blush",
    "\U0001F642": "smile",
    "\U0001F44D": "like yes ok approve +1",
    "\U0001F44E": "dislike no -1",
    "❤️": "love like",
    "\U0001F60D": "love",
    "\U0001F618": "kiss love",
    "\U0001F64F": "thanks thank you please pray",
    "\U0001F62E": "wow surprised",
    "\U0001F632": "wow surprised shocked",
    "\U0001F622": "sad tear",
    "\U0001F62D": "sad sob",
    "\U0001F525": "lit hot",
    "\U0001F389": "party celebrate tada congrats",
    "\U0001F973": "party celebrate birthday",
    "\U0001F44F": "clap applause bravo",
    "\U0001F4AF": "hundred perfect",
    "\U0001F914": "hmm think",
    "\U0001F44C": "ok perfect",
    "✅": "done yes check",
    "\U0001F440": "look see",
    "\U0001F91D": "deal agree",
    "\U0001F4AA": "strong muscle",
    "\U0001F605": "phew nervous",
    "\U0001F644": "whatever",
    "\U0001F621": "angry mad",
    "\U0001F620": "angry mad",
}

LINE = re.compile(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$")


def main(path):
    version = "?"
    group = subgroup = None
    groups, subgroups, subgroup_group = [], [], []
    records, record_subgroup = [], []
    seen = set()
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if line.startswith("# Version:"):
                version = line.split(":", 1)[1].strip()
            elif line.startswith("# group:"):
                group = line.split(":", 1)[1].strip()
                groups.append(group)
            elif line.startswith("# subgroup:"):
                subgroup = line.split(":", 1)[1].strip()
                subgroups.append(subgroup)
                subgroup_group.append(len(groups) - 1)
            match = LINE.match(line)
            if not match:
                continue
            points = [int(p, 16) for p in match.group(1).split()]
            if any(p in SKIN_TONES for p in points):
                continue
            emoji = "".join(chr(p) for p in points)
            name = match.group(3).strip()
            assert "|" not in name and "\n" not in name, name
            assert emoji not in seen, name
            seen.add(emoji)
            records.append(f"{emoji}|{name}|{ALIASES.get(emoji, '')}")
            record_subgroup.append(len(subgroups) - 1)
    missing = set(ALIASES) - seen
    assert not missing, missing
    assert len(subgroups) < 256 and len(records) < 65535

    out = sys.stdout
    out.write(f'pub const unicode_version = "{version}";\n\n')
    out.write("pub const group_names = [_][]const u8{\n")
    for name in groups:
        out.write(f'    "{name}",\n')
    out.write("};\n\n")
    out.write("pub const subgroup_names = [_][]const u8{\n")
    for name in subgroups:
        out.write(f'    "{name}",\n')
    out.write("};\n\n")
    out.write("pub const subgroup_group = [_]u8{\n")
    for index in range(0, len(subgroup_group), 24):
        out.write("    " + ", ".join(str(v) for v in subgroup_group[index:index + 24]) + ",\n")
    out.write("};\n\n")
    out.write("pub const record_subgroup = [_]u8{\n")
    for index in range(0, len(record_subgroup), 24):
        out.write("    " + ", ".join(str(v) for v in record_subgroup[index:index + 24]) + ",\n")
    out.write("};\n\n")
    out.write("pub const records =\n")
    for record in records:
        out.write(f"    \\\\{record}\n")
    out.write(";\n")


if __name__ == "__main__":
    main(sys.argv[1])
