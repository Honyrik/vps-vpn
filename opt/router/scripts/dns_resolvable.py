#!/usr/bin/env python3
"""
Читает список DNS-имён, проверяет разрешимость через системный резолвер
и печатает уникальные имена, которые успешно резолвятся (A/AAAA).
"""

from __future__ import annotations

import argparse
import socket
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Iterable, List, Tuple


def _tokens_from_lines(lines: Iterable[str]) -> List[str]:
    out: List[str] = []
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "#" in line:
            line = line.split("#", 1)[0].strip()
        if not line:
            continue
        for token in line.replace(",", " ").split():
            t = token.strip()
            if t:
                out.append(t)
    return out


def _unique_preserve_order(names: Iterable[str], fold: bool) -> List[str]:
    seen: set[str] = set()
    uniq: List[str] = []
    for n in names:
        key = n.casefold() if fold else n
        if key in seen:
            continue
        seen.add(key)
        uniq.append(n)
    return uniq


def _resolve_one(host: str) -> Tuple[str, bool]:
    try:
        socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
        return (host, True)
    except (socket.gaierror, OSError):
        return (host, False)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Оставить только уникальные DNS-имена, которые реально резолвятся."
    )
    parser.add_argument(
        "names",
        nargs="*",
        help="имена; если не указаны — читается stdin",
    )
    parser.add_argument(
        "-f",
        "--file",
        metavar="PATH",
        help="файл: по одному имени в строке или несколько через пробел/запятую",
    )
    parser.add_argument(
        "-t",
        "--timeout",
        type=float,
        metavar="SEC",
        default=5.0,
        help="таймаут на одно имя (сек), по умолчанию 5",
    )
    parser.add_argument(
        "-j",
        "--jobs",
        type=int,
        default=32,
        metavar="N",
        help="число параллельных проверок (по умолчанию 32)",
    )
    parser.add_argument(
        "--case-sensitive",
        action="store_true",
        help="не схлопывать регистр при уникализации (по умолчанию регистр игнорируется)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="на stderr: имена, которые не резолвятся",
    )
    args = parser.parse_args()

    if args.file and args.names:
        parser.error("нельзя одновременно -f и позиционные аргументы")

    if args.file:
        with open(args.file, encoding="utf-8") as fp:
            lines = fp.readlines()
    elif args.names:
        lines = args.names
    else:
        if sys.stdin.isatty():
            parser.print_help()
            sys.exit(2)
        lines = sys.stdin.readlines()

    tokens = _tokens_from_lines(lines)
    fold = not args.case_sensitive
    hosts = _unique_preserve_order(tokens, fold=fold)
    if not hosts:
        return

    workers = max(1, min(args.jobs, len(hosts)))
    results: dict[str, bool] = {}

    with ThreadPoolExecutor(max_workers=workers) as ex:
        future_map = {ex.submit(_resolve_one, h): h for h in hosts}
        for fut in as_completed(future_map):
            h = future_map[fut]
            try:
                name, ok = fut.result(timeout=args.timeout)
            except TimeoutError:
                name, ok = h, False
            except Exception:
                name, ok = h, False
            results[name] = ok

    for h in hosts:
        if results.get(h):
            print(h)

    if args.verbose:
        bad = sorted({h for h in hosts if not results.get(h)})
        for h in bad:
            print(h, file=sys.stderr)


if __name__ == "__main__":
    main()
