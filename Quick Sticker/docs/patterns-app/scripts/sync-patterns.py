#!/usr/bin/env python3
"""Копирует docs/patterns/*.tgv в public/patterns и пишет manifest.json.

Названия проставлены по содержимому листов — каждый был отрендерен и просмотрен.
Незнакомый файл получит имя «Без названия»: добавьте его в NAMES и перезапустите.

    python3 scripts/sync-patterns.py
"""
import gzip
import json
import os
import re

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(APP), "patterns")
DST = os.path.join(APP, "public", "patterns")

# слаг или fileId → название по рисунку на листе
NAMES = {
    # вшитые в исходники Telegram-iOS
    "fqv01SQemVIBAAAApND8LDRUhRU": "Doodles",
    "Ye7DfT2kCVIKAAAAhzXfrkdOjxs": "Cats & Dogs",
    # из кэша клиента
    "5782630687571969871": "Snowflakes",
    "5785343895722264360": "Math",
    "5789856918507882132": "Christmas",
    "5911275789994690585": "Magic",
    "5911348641229966652": "Animals",
    "5911510226489576101": "Star Wars",
    "5924577350955046421": "Love",
    "5924650004621823334": "Zoo",
    "5924664689115007842": "Unicorns",
    "5925009274341165314": "Games",
    "5926965009174236185": "Beach",
    "5935747671833709896": "Space",
    "5935909802554165816": "Zoo",
    "5935950531729033666": "Paris",
    "5935983444063423035": "Christmas",
    "5936306687597087418": "Sweets",
    "5938052961170098801": "Tattoos",
    "5938074474661284850": "Fantasy",
    "5938102022581521601": "Games",
    "5938141815453518446": "Underwater",
    "5938158372552444547": "Late Night",
    "5938195764537723401": "Astronaut Cats",
    "5938359140798696416": "Unicorns",
    "5938515597867354374": "Beach",
}

BUILTIN_SLUGS = {
    "fqv01SQemVIBAAAApND8LDRUhRU": "обои по умолчанию, вшиты в исходники",
    "Ye7DfT2kCVIKAAAAhzXfrkdOjxs": "старые обои, вшиты в исходники",
}

DRAWABLE = ("path", "circle", "rect", "line ", "polygon", "ellipse", "polyline")


def fill_frame(svg: str) -> str:
    """Лист должен заполнять кадр целиком.

    Пропорция листа (1440×2960 ≈ 0.487) не совпадает с экраном iPhone (1125×2436 ≈ 0.462),
    поэтому по умолчанию SVG вписывается по ширине и сверху-снизу остаются пустые полосы.
    preserveAspectRatio="xMidYMid slice" — это масштаб «заполнить, лишнее обрезать»,
    ровно как обои растягиваются на экран в клиенте.
    """
    root = re.search(r"<svg[^>]*>", svg).group(0)
    if "preserveAspectRatio" in root:
        fixed = re.sub(r'preserveAspectRatio="[^"]*"',
                       'preserveAspectRatio="xMidYMid slice"', root)
    else:
        fixed = root[:-1] + ' preserveAspectRatio="xMidYMid slice">'
    return svg.replace(root, fixed, 1)


def count_elements(svg: str) -> int:
    return sum(svg.count("<" + tag) for tag in DRAWABLE)


def main():
    os.makedirs(DST, exist_ok=True)
    for stale in os.listdir(DST):
        os.remove(os.path.join(DST, stale))

    items = []
    for fn in sorted(os.listdir(SRC)):
        if not fn.endswith(".tgv"):
            continue
        stem = fn[:-4]
        ident = stem.replace("cache-", "")
        svg = gzip.open(os.path.join(SRC, fn), "rb").read().decode("utf-8")
        view_box = (re.search(r'viewBox="([^"]+)"', svg) or [None, ""])[1]
        parts = view_box.split()
        width, height = (parts[2], parts[3]) if len(parts) == 4 else ("?", "?")
        with gzip.open(os.path.join(DST, fn), "wb") as out:
            out.write(fill_frame(svg).encode("utf-8"))

        items.append({
            "file": "patterns/" + fn,
            "id": ident,
            "title": NAMES.get(ident, "Untitled"),
            "origin": BUILTIN_SLUGS.get(ident, "из кэша клиента, fileId " + ident),
            "width": width,
            "height": height,
            "elements": count_elements(svg),
            "svgBytes": len(svg),
            "builtin": ident in BUILTIN_SLUGS,
        })

    # один сюжет встречается в нескольких прорисовках — нумеруем, чтобы имена не дублировались
    counts = {}
    for item in items:
        counts[item["title"]] = counts.get(item["title"], 0) + 1
    seen = {}
    for item in sorted(items, key=lambda i: (i["title"], i["elements"])):
        title = item["title"]
        if counts[title] > 1:
            seen[title] = seen.get(title, 0) + 1
            if seen[title] > 1:
                item["title"] = "%s %s" % (title, "II III IV V".split()[seen[title] - 2])

    items.sort(key=lambda i: (not i["builtin"], i["title"]))
    with open(os.path.join(DST, "manifest.json"), "w") as f:
        json.dump(items, f, ensure_ascii=False, indent=1)

    print("паттернов: %d" % len(items))
    for item in items:
        print("  %-24s %s" % (item["title"], item["id"]))


if __name__ == "__main__":
    main()
