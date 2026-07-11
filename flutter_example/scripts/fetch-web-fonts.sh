#!/usr/bin/env bash
# Download bundled Noto Sans SC for Flutter Web (google_fonts expects *-Regular.ttf).
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)/google_fonts"
mkdir -p "$DIR"
REG="$DIR/NotoSansSC-Regular.ttf"
BOLD="$DIR/NotoSansSC-Bold.ttf"
SRC="$DIR/.NotoSansSC-src.ttf"

if [[ -f "$REG" && -f "$BOLD" ]]; then
  echo "fonts ok: $REG $BOLD"
  exit 0
fi

if [[ ! -f "$SRC" ]]; then
  LEGACY="$DIR/NotoSansSC-400.ttf"
  if [[ -f "$LEGACY" ]]; then
    cp -f "$LEGACY" "$SRC"
    echo "→ reuse $LEGACY"
  else
    echo "→ downloading NotoSansSC → $SRC"
    curl -fsSL \
      "https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf" \
      -o "$SRC"
    echo "✓ $(wc -c < "$SRC") bytes"
  fi
fi

cp -f "$SRC" "$REG"
cp -f "$SRC" "$BOLD"
echo "✓ bundled $REG and $BOLD"
