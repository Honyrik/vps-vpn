#!/usr/bin/env python3
"""
Схлопывает список IP-адресов и подсетей в минимальный набор непересекающихся CIDR.
Использует стандартный модуль ipaddress (Python 3.3+).
"""

from __future__ import annotations

import argparse
import ipaddress
import sys
from typing import Iterable, List, Union


def _parse_token(s: str) -> Union[ipaddress.IPv4Network, ipaddress.IPv6Network]:
    s = s.strip()
    if not s:
        raise ValueError("пустая строка")
    if "/" in s:
        return ipaddress.ip_network(s, strict=False)
    addr = ipaddress.ip_address(s)
    if addr.version == 4:
        return ipaddress.IPv4Network((addr, 32), strict=False)
    return ipaddress.IPv6Network((addr, 128), strict=False)


def collect_networks(lines: Iterable[str]) -> tuple[List, List]:
    v4: Set = []
    v6: Set = []
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "#" in line:
            line = line.split("#", 1)[0].strip()
        if not line:
            continue
        for token in line.replace(",", " ").split():
            token = token.strip()
            if not token:
                continue
            net = _parse_token(token)
            if net.version == 4:
                v4.append(net)
            else:
                v6.append(net)
    return list(sorted(v4)), list(sorted(v6))


def collapse_lines(lines: Iterable[str]) -> List[str]:
    v4, v6 = collect_networks(lines)
    out: List[str] = []
    if v4:
        out.extend(str(n) for n in sorted(ipaddress.collapse_addresses(v4)))
    if v6:
        out.extend(str(n) for n in sorted(ipaddress.collapse_addresses(v6)))
    return out


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Схлопнуть IP и подсети в минимальный набор CIDR."
    )
    parser.add_argument(
        "items",
        nargs="*",
        help="IP или CIDR; если не указано — читается stdin",
    )
    parser.add_argument(
        "-f",
        "--file",
        metavar="PATH",
        help="файл: по одному IP/CIDR в строке (или несколько через пробел/запятую)",
    )
    args = parser.parse_args()

    if args.file and args.items:
        parser.error("нельзя одновременно -f и позиционные аргументы")

    if args.file:
        with open(args.file, encoding="utf-8") as f:
            lines = f.readlines()
    elif args.items:
        lines = args.items
    else:
        if sys.stdin.isatty():
            parser.print_help()
            sys.exit(2)
        lines = sys.stdin.readlines()

    try:
        for net in collapse_lines(lines):
            print(net)
    except ValueError as e:
        print(f"ошибка разбора: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
