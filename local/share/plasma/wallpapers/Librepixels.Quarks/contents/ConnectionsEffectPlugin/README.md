# ConnectionsEffect (plugin QML en C++)

Reemplazo del efecto original en `Canvas` por un `QQuickItem` que dibuja
puntos y conexiones directamente en la scene graph de Qt Quick, usando
`QSGGeometryNode` (primitivas GPU nativas: triangulos para los puntos,
`GL_LINES` para las conexiones). Sin rasterizado 2D en CPU, sin subir una
textura completa cada frame.

## Dependencias

Solo Qt6 (`Core`, `Gui`, `Qml`, `Quick`) — los mismos modulos que ya
necesita cualquier widget/wallpaper de Plasma 6. No se usa KF6, ECM ni
ninguna libreria externa: el paquete `qt6-base`/`qt6-declarative` (o como
se llame en tu distro) alcanza.

Si tu entorno todavia es Plasma 5 / Qt5, avisame y te adapto el
`CMakeLists.txt` y el registro del tipo QML (Qt5 no tiene `qt_add_qml_module`
ni `QML_ELEMENT`; se hace con `qmlRegisterType` + `qmldir` manual).

## Build

```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build .
```

Esto genera `build/ConnectionsEffect/` con:
- `libconnectionseffectplugin.so`
- `qmldir`
- `ConnectionsEffect.qmltypes`

Esa carpeta completa **es** el modulo distribuible — se mueve como bloque.

## Integrarlo a tu wallpaper/widget

**Opcion A — paquete de sistema (recomendado para distribuir):**

```bash
cmake --install build
```

Instala el modulo en el import path estandar de Qt
(`qmake6 -query QT_INSTALL_QML`), detectado automaticamente por el
`CMakeLists.txt`. Empaquetalo como dependencia de tu paquete deb/rpm/AUR
del widget — es exactamente como se distribuyen la mayoria de plugins QML
en C++ del ecosistema KDE, así que en cualquier maquina con Plasma 6 el
import `import ConnectionsEffect 1.0` va a funcionar sin pasos extra.

**Opcion B — bundleado junto al paquete del wallpaper, sin instalar:**

Copia la carpeta `ConnectionsEffect/` generada por el build dentro de tu
package (p. ej. `contents/ui/ConnectionsEffect/`). Como Plasma carga el
wallpaper con un `QQmlEngine` propio, necesitas agregar esa ruta al import
path del motor. Si tu wallpaper es puramente QML (sin C++ propio), la via
mas simple es fijar la variable de entorno antes de que arranque
`plasmashell`:

```bash
export QML2_IMPORT_PATH="$HOME/.local/share/plasma/wallpapers/tu-paquete/contents/ui:$QML2_IMPORT_PATH"
```

Si en cambio tenes (o podes agregar) un pequeno host en C++ para el
wallpaper, la forma limpia es `engine->addImportPath(...)` apuntando a la
carpeta bundleada, sin tocar variables de entorno del sistema.

## Reemplazo en QML

Ver `ExampleUsage.qml`. En resumen, donde antes tenias
`Rectangle { Canvas { ... } }`, ahora es:

```qml
import ConnectionsEffect 1.0

ConnectionsEffect {
    anchors.fill: parent
    level: root.configuration.level
    connectionsLevel: root.configuration.connectionsLevel
    lineColor: root.configuration.quarksColor
    running: root.visible
}
```

Propiedades expuestas: `level`, `connectionsLevel`, `lineColor`,
`pointSize`, `animationSpeed`, `running`, `pointCount` (solo lectura, util
para debug/telemetria).

## Notas de implementacion

- La simulacion (rebotes, atraccion al centro, jitter) es una traduccion
  1:1 de `updatePositions()` del QML original.
- Las conexiones usan el mismo grid espacial (hash de celdas) que la
  version Canvas, para no volver a O(n²) puro.
- El buffer de vertices solo se reasigna (`allocate`) cuando cambia la
  cantidad de puntos/conexiones; si el conteo es igual al frame anterior,
  se reescribe el buffer existente — evita churn de memoria innecesario.
- Los puntos se dibujan como octagonos (8 triangulos) en vez de circulos
  perfectos via arco, para no depender de point sprites (que no son
  portables entre los distintos backends de RHI de Qt6 — GL/Vulkan/Metal/D3D).
  Con `pointSize` chico (2-3px) la diferencia visual es imperceptible.
- `running` pausa el timer interno cuando el item no es visible (o vos lo
  fijas en `false`), asi no se gasta CPU/GPU si el wallpaper esta oculto
  detras de una ventana maximizada, por ejemplo.

## Posibles siguientes optimizaciones (no incluidas, por mantenerlo simple)

- Mover `updatePositions()` a un hilo aparte si `numPoints` llega a ser
  muy alto (miles), aunque para un efecto de wallpaper tipico no deberia
  hacer falta.
- Usar un `QSGGeometry` con menos segmentos por punto (`kOctagonSegments`)
  en pantallas muy chicas o con `pointSize` diminuto, ya que a esa escala
  un hexagono o incluso un cuadrado es indistinguible.
