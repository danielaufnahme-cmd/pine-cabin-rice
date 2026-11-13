cmake_minimum_required(VERSION 3.16)
project(ConnectionsEffectPlugin VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Unicas dependencias: los modulos base de Qt6 que ya trae cualquier
# sistema con Plasma 6 (no se necesita KF6, ECM ni nada fuera de Qt).
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)

qt_add_qml_module(connectionseffectplugin
    URI ConnectionsEffect
    VERSION 1.0
    PLUGIN_TARGET connectionseffectplugin
    SOURCES
        connectionseffectitem.h
        connectionseffectitem.cpp
)

target_link_libraries(connectionseffectplugin PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
)

# qt_add_qml_module ya genera el qmldir y deja todo listo en:
#   ${CMAKE_CURRENT_BINARY_DIR}/ConnectionsEffect/
# (libconnectionseffectplugin.so + qmldir + ConnectionsEffect.qmltypes)
#
# --- Opcion A: instalar en el import path estandar de Qt (recomendado) ---
# Sirve para empaquetar como paquete de la distro (deb/rpm/AUR) junto al
# widget/wallpaper. No requiere ECM ni KDE Install Dirs.
execute_process(
    COMMAND ${CMAKE_CXX_COMPILER} -dumpversion
    OUTPUT_QUIET ERROR_QUIET
)
find_program(QMAKE6_EXECUTABLE NAMES qmake6 qmake)
if(QMAKE6_EXECUTABLE)
    execute_process(
        COMMAND ${QMAKE6_EXECUTABLE} -query QT_INSTALL_QML
        OUTPUT_VARIABLE QT_QML_INSTALL_DIR
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
endif()
if(NOT QT_QML_INSTALL_DIR)
    set(QT_QML_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}/lib/qt6/qml")
endif()

install(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/ConnectionsEffect/"
    DESTINATION "${QT_QML_INSTALL_DIR}/ConnectionsEffect"
    FILES_MATCHING
        PATTERN "*.so"
        PATTERN "qmldir"
        PATTERN "*.qmltypes"
)

# --- Opcion B: uso local sin instalar (desarrollo o bundling manual) ---
# Copia a mano la carpeta ${CMAKE_CURRENT_BINARY_DIR}/ConnectionsEffect/
# a donde quieras distribuirla (p.ej. dentro del paquete del wallpaper) y
# agrega esa ruta al import path de QML con la variable de entorno
# QML2_IMPORT_PATH, o con QQmlEngine::addImportPath() si tenes un host
# en C++ (ver README.md).
