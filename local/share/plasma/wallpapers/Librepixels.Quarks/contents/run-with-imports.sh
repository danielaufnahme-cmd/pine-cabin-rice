#!/usr/bin/env bash
# Lanza cualquier programa QML con la carpeta imports/ de tu proyecto en el import path.
# Uso:  ./run-with-imports.sh qml6 main.qml
#       ./run-with-imports.sh ./mi_app
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export QML_IMPORT_PATH="$DIR/imports${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
export QML2_IMPORT_PATH="$QML_IMPORT_PATH"
exec "$@"
