#!/usr/bin/env python3
"""Скачивает паттерны обоев Telegram в docs/patterns/ и обновляет приложение.

Паттерны — это документы в облаке Telegram; отдаёт их только MTProto-метод
account.getWallPaper / account.getWallPapers, доступный лишь авторизованной сессии.
Поэтому скрипт логинится ВАШИМ аккаунтом: код подтверждения вводите вы, локально.

    pip install telethon
    python3 docs/fetch-patterns.py --login      # разовый вход: api_id, телефон и код вводите вы
    python3 docs/fetch-patterns.py              # 16 встроенных слагов
    python3 docs/fetch-patterns.py --all        # + вся коллекция обоев с сервера

Файлы .tgv складываются в docs/patterns/, затем patterns-app/scripts/sync-patterns.py
раскладывает их в public/ приложения и пересобирает manifest.json.
Повторный запуск идемпотентен: уже скачанные файлы не перекачиваются.
"""

import argparse
import getpass
import gzip
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATTERN_DIR = os.path.join(HERE, "patterns")
SYNC = os.path.join(HERE, "patterns-app", "scripts", "sync-patterns.py")

# submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift → BuiltinWallpaperData
BUILTIN_SLUGS = [
    ("default",   "fqv01SQemVIBAAAApND8LDRUhRU"),
    ("legacy",    "Ye7DfT2kCVIKAAAAhzXfrkdOjxs"),
    ("variant1",  "RlZs2PJkSFADAAAAElGaGwgJBgU"),
    ("variant2",  "9LW_RcoOSVACAAAAFTk3DTyXN-M"),
    ("variant3",  "CJNyxPMgSVAEAAAAvW9sMwc51cw"),
    ("variant4",  "BQqgrGnjSFABAAAA8mQDBXQcARE"),
    ("variant5",  "MIo6r0qGSFAFAAAAtL8TsDzNX60"),
    ("variant6",  "9iklpvIPQVABAAAAORQXKur_Eyc"),
    ("variant7",  "H6rz6geXUFIMAAAAuUs7m6cXbcc"),
    ("variant8",  "kO4jyq55SFABAAAA0WEpcLfahXk"),
    ("variant9",  "mP3FG_iwSFAFAAAA2AklJO978pA"),
    ("variant10", "Ujx2TFcJSVACAAAARJ4vLa50MkM"),
    ("variant11", "RepJ5uE_SVABAAAAr4d0YhgB850"),
    ("variant12", "9GcNVISdSVADAAAAUcw5BYjELW4"),
    ("variant13", "-Xc-np9y2VMCAAAARKr0yNNPYW0"),
    ("variant14", "JrNEYdNhSFABAAAA9WtRdJkPRbY"),
]


def minify_svg(svg: str) -> str:
    svg = re.sub(r"<\?xml[^>]*\?>", "", svg)
    svg = re.sub(r"<!--.*?-->", "", svg, flags=re.S)
    return re.sub(r">\s+<", "><", svg).strip()


def sync_app(count):
    """Отдаёт скачанные .tgv приложению: копирует в public/ и пересобирает манифест."""
    print("паттернов в docs/patterns: %d" % count)
    subprocess.run([sys.executable, SYNC], check=False)


SESSION = os.path.join(HERE, ".tg-patterns.session")
CREDS = os.path.join(HERE, ".tg-credentials.json")


TG_GROUP = os.path.expanduser(
    "~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram")


def scan_cache(roots=None):
    """Ищет в кэше Telegram для macOS файлы-паттерны: gzip, внутри SVG.

    Никакого API и авторизации: клиент уже скачал их, когда показывал выбор обоев.
    Читаются только файлы, у которых первые два байта — сигнатура gzip, а под ней SVG.
    """
    import hashlib

    if roots is None:
        roots = [TG_GROUP]
    by_hash = {}
    for root in roots:
        for dirpath, _, files in os.walk(root):
            for fn in files:
                path = os.path.join(dirpath, fn)
                try:
                    if not (3_000 < os.path.getsize(path) < 2_000_000):
                        continue
                    with open(path, "rb") as f:
                        if f.read(2) != b"\x1f\x8b":
                            continue
                    with gzip.open(path, "rb") as g:
                        head = g.read(200)
                    if b"<svg" not in head:
                        continue
                    svg = minify_svg(gzip.open(path, "rb").read().decode("utf-8"))
                except Exception:
                    continue
                digest = hashlib.md5(svg.encode()).hexdigest()[:10]
                if digest in by_hash:
                    continue
                file_id = re.search(r"telegram-cloud-document-\d+-(\d+)", fn)
                by_hash[digest] = (file_id.group(1) if file_id else digest, path)
    return by_hash


def collect_from_cache():
    os.makedirs(PATTERN_DIR, exist_ok=True)
    items = []
    for digest, (file_id, src) in sorted(scan_cache().items()):
        dest = os.path.join(PATTERN_DIR, "cache-%s.tgv" % file_id)
        if not os.path.exists(dest):
            with open(src, "rb") as fsrc, open(dest, "wb") as fdst:
                fdst.write(fsrc.read())
        items.append(("cache-%s" % file_id, "fileId %s" % file_id, dest))
        print("  fileId %-22s → %s (%d КБ)" % (file_id, os.path.basename(dest),
                                               os.path.getsize(dest) // 1024))
    print("уникальных паттернов в кэше: %d" % len(items))
    return items


def credentials(ask=False):
    """api_id/api_hash: из переменных окружения, из локального файла или спросить (только при --login)."""
    api_id = os.environ.get("TG_API_ID")
    api_hash = os.environ.get("TG_API_HASH")

    if (not api_id or not api_hash) and os.path.exists(CREDS):
        saved = json.load(open(CREDS))
        api_id, api_hash = saved.get("api_id"), saved.get("api_hash")

    if (not api_id or not api_hash) and ask:
        print("api_id и api_hash берутся на https://my.telegram.org → API development tools")
        api_id = input("api_id: ").strip()
        api_hash = getpass.getpass("api_hash (ввод скрыт): ").strip()
        json.dump({"api_id": int(api_id), "api_hash": api_hash}, open(CREDS, "w"))
        os.chmod(CREDS, 0o600)
        print("сохранил в %s (в .gitignore, в чат не попадает)" % os.path.basename(CREDS))

    if not api_id or not api_hash:
        sys.exit("нет api_id/api_hash — выполните: python3 docs/fetch-patterns.py --login")

    return int(api_id), api_hash


async def login():
    """Разовый интерактивный вход. Запускать в своём терминале: код вводите вы."""
    from telethon import TelegramClient

    api_id, api_hash = credentials(ask=True)
    client = TelegramClient(SESSION, api_id, api_hash)
    await client.start()   # спросит телефон, код, при необходимости пароль 2FA
    me = await client.get_me()
    print("вошли как %s (id %s); сессия: %s.session" % (me.first_name, me.id, SESSION))
    await client.disconnect()


async def check():
    from telethon import TelegramClient

    api_id, api_hash = credentials()
    client = TelegramClient(SESSION, api_id, api_hash)
    await client.connect()
    try:
        if await client.is_user_authorized():
            me = await client.get_me()
            print("сессия готова: %s (id %s)" % (me.first_name, me.id))
        else:
            print("сессии нет — выполните: python3 docs/fetch-patterns.py --login")
    finally:
        await client.disconnect()


async def download(all_wallpapers: bool):
    from telethon import TelegramClient, functions, types

    api_id, api_hash = credentials()
    os.makedirs(PATTERN_DIR, exist_ok=True)
    targets = list(BUILTIN_SLUGS)
    saved = []

    # connect(), а не start(): start() спросил бы телефон, а этот шаг должен быть неинтерактивным
    client = TelegramClient(SESSION, api_id, api_hash)
    await client.connect()
    try:
        if not await client.is_user_authorized():
            sys.exit("сессии нет — сначала выполните: python3 docs/fetch-patterns.py --login")
        if all_wallpapers:
            result = await client(functions.account.GetWallPapersRequest(hash=0))
            for wp in result.wallpapers:
                if isinstance(wp, types.WallPaper) and wp.pattern and wp.slug:
                    if wp.slug not in [s for _, s in targets]:
                        targets.append(("cloud-" + wp.slug[:12], wp.slug))
            print("на сервере паттернов всего: %d" % len(targets))

        for name, slug in targets:
            dest = os.path.join(PATTERN_DIR, "%s.tgv" % slug)
            if not os.path.exists(dest):
                wp = await client(functions.account.GetWallPaperRequest(
                    wallpaper=types.InputWallPaperSlug(slug=slug)))
                if not isinstance(wp, types.WallPaper):
                    print("  %-10s %s — не документ, пропуск" % (name, slug))
                    continue
                await client.download_media(wp.document, file=dest)
            print("  %-10s %s → %s (%d КБ)" % (name, slug, os.path.basename(dest),
                                               os.path.getsize(dest) // 1024))
            saved.append((name, slug, dest))
    finally:
        await client.disconnect()

    return saved


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="забрать ещё и всю серверную коллекцию обоев")
    ap.add_argument("--sync-only", action="store_true", help="ничего не качать, только пересобрать манифест приложения")
    ap.add_argument("--login", action="store_true", help="разовый интерактивный вход (телефон и код вводите вы)")
    ap.add_argument("--check", action="store_true", help="проверить, есть ли рабочая сессия (без интерактива)")
    ap.add_argument("--from-cache", action="store_true",
                    help="без всякого API: вытащить паттерны из кэша Telegram для macOS")
    args = ap.parse_args()

    if args.from_cache:
        sync_app(len(collect_from_cache()))
        return

    if args.sync_only:
        sync_app(len([f for f in os.listdir(PATTERN_DIR) if f.endswith(".tgv")]))
        return

    import asyncio
    if args.check:
        asyncio.run(check())
        return

    if args.login:
        asyncio.run(login())
        return

    sync_app(len(asyncio.run(download(args.all))))


if __name__ == "__main__":
    main()
