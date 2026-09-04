#!/usr/bin/env python3
"""Report gaps between generated recipes and built conda artifacts.

Default behavior is platform-agnostic: it inspects all output/<platform> folders that
contain conda artifacts and reports gaps per platform.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Iterable, Set

CONDA_SUFFIX = ".conda"
TARBZ2_SUFFIX = ".tar.bz2"

# check_patches_clean_apply.py builds throwaway "<pkg>-check-patches[-<platform>]"
# packages into this same output/<platform> folder to verify patches apply (the
# platform suffix was added later; older leftover artifacts may lack it). They
# never have a matching recipes/ directory and would otherwise show up as false
# "built but no recipe" gaps.
_CHECK_PATCHES_RE = re.compile(r'-check-patches(?:-(?:linux|osx|win|emscripten|any))?$')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compare recipe directories with built package artifacts and report gaps. "
            "By default, checks every platform folder found under output/."
        )
    )
    parser.add_argument(
        "--output-dir",
        default="output",
        help="Output root directory containing platform subfolders (default: output)",
    )
    parser.add_argument(
        "--recipes-dir",
        default="recipes",
        help="Recipes directory (default: recipes)",
    )
    parser.add_argument(
        "--platform",
        action="append",
        default=[],
        help=(
            "Platform folder to inspect (repeatable). "
            "If omitted, all detected platform folders are inspected."
        ),
    )
    return parser.parse_args()


def is_conda_artifact(filename: str) -> bool:
    return filename.endswith(CONDA_SUFFIX) or filename.endswith(TARBZ2_SUFFIX)


def package_name_from_artifact(filename: str) -> str | None:
    stem = filename
    if stem.endswith(CONDA_SUFFIX):
        stem = stem[: -len(CONDA_SUFFIX)]
    elif stem.endswith(TARBZ2_SUFFIX):
        stem = stem[: -len(TARBZ2_SUFFIX)]
    else:
        return None

    parts = stem.rsplit("-", 2)
    if len(parts) != 3:
        return None
    name = parts[0]
    if _CHECK_PATCHES_RE.search(name):
        return None
    return name


def discover_platform_dirs(output_root: Path) -> list[str]:
    platforms: list[str] = []
    if not output_root.exists():
        return platforms

    for child in sorted(output_root.iterdir()):
        if not child.is_dir():
            continue
        try:
            has_artifact = any(
                entry.is_file() and is_conda_artifact(entry.name)
                for entry in child.iterdir()
            )
        except PermissionError:
            continue
        if has_artifact:
            platforms.append(child.name)

    return platforms


def built_packages_for_platform(output_root: Path, platform: str) -> Set[str]:
    platform_dir = output_root / platform
    packages: Set[str] = set()
    if not platform_dir.exists() or not platform_dir.is_dir():
        return packages

    for artifact in platform_dir.iterdir():
        if not artifact.is_file() or not is_conda_artifact(artifact.name):
            continue
        package_name = package_name_from_artifact(artifact.name)
        if package_name:
            packages.add(package_name)

    return packages


def recipe_directories(recipes_dir: Path) -> Set[str]:
    if not recipes_dir.exists():
        return set()
    return {entry.name for entry in recipes_dir.iterdir() if entry.is_dir()}


def print_list(title: str, values: Iterable[str]) -> None:
    values = sorted(values)
    print(f"{title}: {len(values)}")
    if values:
        for value in values:
            print(f"  - {value}")


def main() -> int:
    args = parse_args()
    output_root = Path(args.output_dir)
    recipes_dir = Path(args.recipes_dir)

    recipes = recipe_directories(recipes_dir)
    if not recipes:
        print(f"No recipe directories found in: {recipes_dir}")
        return 1

    selected_platforms = args.platform or discover_platform_dirs(output_root)
    if not selected_platforms:
        print(
            "No platform artifact folders found under "
            f"{output_root} (expected e.g. output/osx-arm64, output/linux-64)."
        )
        return 1

    for idx, platform in enumerate(selected_platforms):
        built = built_packages_for_platform(output_root, platform)

        print(f"Platform: {platform}")
        print_list(
            "Built package artifacts without matching recipe directory",
            built - recipes,
        )
        print()
        missing = recipes - built
        print(
            f"Recipe directories without built artifact on {platform} platform: "
            f"{len(missing)} out of {len(recipes)}"
        )
        if missing:
            for recipe in sorted(missing):
                print(f"  - {recipe}")

        if idx != len(selected_platforms) - 1:
            print("\n" + "-" * 72 + "\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
