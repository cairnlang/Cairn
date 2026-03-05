#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAPTER_DIR="${ROOT_DIR}/chapters"
DIST_DIR="${ROOT_DIR}/dist"
OUTLINE_FILE="${ROOT_DIR}/outline.md"
OUTPUT_FILE="${DIST_DIR}/runewarden.md"

mkdir -p "${DIST_DIR}"

{
  echo "# Runewarden"
  echo
  echo "_Generated on $(date -u '+%Y-%m-%d %H:%M:%S UTC')_"
  echo
} > "${OUTPUT_FILE}"

while IFS= read -r line; do
  case "${line}" in
    [0-9][0-9].*)
      chapter_file="${line#*. }"
      chapter_path="${CHAPTER_DIR}/${chapter_file}"

      if [[ ! -f "${chapter_path}" ]]; then
        echo "missing chapter file: ${chapter_path}" >&2
        exit 1
      fi

      {
        echo
        echo "---"
        echo
        cat "${chapter_path}"
      } >> "${OUTPUT_FILE}"
      ;;
  esac
done < "${OUTLINE_FILE}"

echo "built ${OUTPUT_FILE}"
