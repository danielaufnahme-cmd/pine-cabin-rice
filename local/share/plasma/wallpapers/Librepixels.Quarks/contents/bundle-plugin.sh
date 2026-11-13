#!/usr/bin/env bash
# Compila ConnectionsEffectPlugin y deja el módulo listo dentro de tu proyecto:
#   <proyecto>/imports/ConnectionsEffect/{qmldir, libconnectionseffectplugin.so}
#
# Uso:  ./bundle-plugin.sh /ruta/a/ConnectionsEffectPlugin /ruta/a/mi-proyecto
set -euo pipefail

SRC="${1:?Falta ruta al código del plugin (carpeta con CMakeLists.txt)}"
PROJ="${2:?Falta ruta a tu proyecto}"
BUILD="$(mktemp -d)"
DEST="$PROJ/imports/ConnectionsEffect"

cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" -j"$(nproc)"

SO="$(find "$BUILD" -name 'libconnectionseffectplugin.so' | head -n1)"
[ -n "$SO" ] || { echo "No se generó el .so" >&2; exit 1; }

mkdir -p "$DEST"
cp "$SO" "$DEST/"

# qmldir manual (el generado por CMake apunta a :/ConnectionsEffect/ y no sirve aquí)
cat > "$DEST/qmldir" <<QMLDIR
module ConnectionsEffect
plugin connectionseffectplugin
ConnectionsEffectView 1.0 ConnectionsEffectView.qml
QMLDIR

echo "Listo: $DEST"
ls -l "$DEST"
