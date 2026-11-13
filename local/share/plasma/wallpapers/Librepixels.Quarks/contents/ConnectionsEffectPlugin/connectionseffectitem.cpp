#include "connectionseffectitem.h"

#include <QAbstractAnimation>
#include <QSGNode>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>
#include <QRandomGenerator>
#include <QHash>
#include <QSet>
#include <QPointF>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace {
// Paso fijo de la simulacion: 60 pasos/s (equivale al ritmo del Timer QML original
// en una pantalla de 60 Hz). El render interpola entre pasos.
constexpr qreal kStepMs = 1000.0 / 60.0;
constexpr qreal kMaxFrameMs = 100.0;   // evita "saltos" tras una pausa
constexpr int kHardSegments = 8;       // octagono si softEdges = false
constexpr int kSoftSegments = 12;      // disco con borde difuminado

inline qint64 cellKey(int cx, int cy)
{
    return (static_cast<qint64>(cx) << 32) ^ static_cast<quint32>(cy);
}

// QSGVertexColorMaterial espera colores PREMULTIPLICADOS por alpha.
inline uchar pm(int c, int a) { return static_cast<uchar>((c * a + 127) / 255); }

inline void setV(QSGGeometry::ColoredPoint2D &v, qreal x, qreal y, int r, int g, int b, int a)
{
    v.set(static_cast<float>(x), static_cast<float>(y), pm(r, a), pm(g, a), pm(b, a), static_cast<uchar>(a));
}
} // namespace

// Animacion "infinita" cuyo updateCurrentTime() se ejecuta una vez por frame,
// sincronizada con el vsync igual que el Timer de QML.
class ConnectionsEffectItem::FrameDriver : public QAbstractAnimation
{
public:
    explicit FrameDriver(ConnectionsEffectItem *item) : QAbstractAnimation(item), m_item(item) {}
    int duration() const override { return -1; }

protected:
    void updateCurrentTime(int) override { m_item->advance(); }

private:
    ConnectionsEffectItem *m_item;
};

ConnectionsEffectItem::ConnectionsEffectItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
    m_driver = new FrameDriver(this);
    m_clock.start();
    recomputeDerivedParams();
}

ConnectionsEffectItem::~ConnectionsEffectItem() = default;

void ConnectionsEffectItem::setLevel(qreal l)
{
    if (qFuzzyCompare(m_level, l)) return;
    m_level = l;
    emit levelChanged();
    recomputeDerivedParams();
    initPoints();
    update();
}

void ConnectionsEffectItem::setConnectionsLevel(int l)
{
    if (m_connectionsLevel == l) return;
    m_connectionsLevel = l;
    emit connectionsLevelChanged();
    recomputeDerivedParams();
    update();
}

void ConnectionsEffectItem::setLineColor(const QColor &c)
{
    if (m_lineColor == c) return;
    m_lineColor = c;
    emit lineColorChanged();
    update();
}

void ConnectionsEffectItem::setPointSize(qreal s)
{
    if (qFuzzyCompare(m_pointSize, s)) return;
    m_pointSize = s;
    emit pointSizeChanged();
    update();
}

void ConnectionsEffectItem::setAnimationSpeed(qreal s)
{
    if (qFuzzyCompare(m_animationSpeed, s)) return;
    m_animationSpeed = s;
    emit animationSpeedChanged();
}

void ConnectionsEffectItem::setRunning(bool r)
{
    if (m_running == r) return;
    m_running = r;
    emit runningChanged();
    ensureDriverState();
}

void ConnectionsEffectItem::setSoftEdges(bool s)
{
    if (m_softEdges == s) return;
    m_softEdges = s;
    emit softEdgesChanged();
    update();
}

void ConnectionsEffectItem::setConnectionThreshold(qreal t)
{
    t = qMax<qreal>(0.0, t);
    if (qFuzzyCompare(m_thresholdOverride + 1.0, t + 1.0)) return;
    m_thresholdOverride = t;
    emit connectionThresholdChanged();
    recomputeDerivedParams();
    update();
}

void ConnectionsEffectItem::setConnectionsFactor(qreal f)
{
    f = qMax<qreal>(0.0, f);
    if (qFuzzyCompare(m_factorOverride + 1.0, f + 1.0)) return;
    m_factorOverride = f;
    emit connectionsFactorChanged();
    recomputeDerivedParams();
    update();
}

void ConnectionsEffectItem::recomputeDerivedParams()
{
    m_density = m_level * 0.3;
    const qreal screenFactor = (width() + height()) / 2.0;
    m_numPoints = qMax(0, qCeil(screenFactor * m_density));

    // Valores automaticos segun connectionsLevel (los del QML original)...
    qreal autoThreshold, autoFactor;
    switch (m_connectionsLevel) {
    case 1:  autoThreshold = 40.0; autoFactor = 1.1; break;
    case 2:  autoThreshold = 38.0; autoFactor = 1.4; break;
    default: autoThreshold = 33.0; autoFactor = 1.6; break;
    }
    // ...que QML puede sustituir con connectionThreshold / connectionsFactor (> 0).
    m_connectionThreshold = m_thresholdOverride > 0.0 ? m_thresholdOverride : autoThreshold;
    m_maxConnections = m_numPoints * (m_factorOverride > 0.0 ? m_factorOverride : autoFactor);
    emit pointCountChanged();
}

void ConnectionsEffectItem::initPoints()
{
    m_points.clear();
    if (width() <= 0 || height() <= 0) {
        return;
    }

    auto *rng = QRandomGenerator::global();
    const qreal centerX = width() / 2.0;
    const qreal centerY = height() / 2.0;
    const qreal maxRadius = qMin(width(), height()) / 2.0;

    m_points.reserve(m_numPoints);
    for (int i = 0; i < m_numPoints; ++i) {
        const qreal angle = rng->generateDouble() * 2.0 * M_PI;
        const qreal rnd = rng->generateDouble();
        const qreal pointRadius = std::pow(rnd, 0.65) * maxRadius;
        const qreal cx = centerX + std::cos(angle) * pointRadius;
        const qreal cy = centerY + std::sin(angle) * pointRadius;
        const qreal moveRadius = (kMovementRangeMin
                                   + rng->generateDouble() * (kMovementRangeMax - kMovementRangeMin))
                                  * maxRadius;

        Point p;
        p.x = p.prevX = cx;
        p.y = p.prevY = cy;
        p.dx = (rng->generateDouble() - 0.5) * m_animationSpeed;
        p.dy = (rng->generateDouble() - 0.5) * m_animationSpeed;
        p.centerX = cx;
        p.centerY = cy;
        p.moveRadius = moveRadius;
        m_points.push_back(p);
    }
    m_alpha = 1.0;
}

// Un paso de simulacion (traduccion 1:1 del Timer del QML original).
void ConnectionsEffectItem::stepSimulation()
{
    auto *rng = QRandomGenerator::global();
    const qreal w = width();
    const qreal h = height();

    for (Point &p : m_points) {
        p.prevX = p.x;
        p.prevY = p.y;

        p.x += p.dx;
        p.y += p.dy;

        if (p.x < kMargin) p.dx += (kMargin - p.x) * 0.07;
        if (p.x > w - kMargin - m_pointSize) p.dx -= (p.x - (w - kMargin - m_pointSize)) * 0.07;
        if (p.y < kMargin) p.dy += (kMargin - p.y) * 0.07;
        if (p.y > h - kMargin - m_pointSize) p.dy -= (p.y - (h - kMargin - m_pointSize)) * 0.07;

        p.dx += (rng->generateDouble() - 0.5) * 0.08;
        p.dy += (rng->generateDouble() - 0.5) * 0.08;

        const qreal speed = std::hypot(p.dx, p.dy);
        if (speed > m_animationSpeed * 1.5) {
            p.dx *= 0.9;
            p.dy *= 0.9;
        }

        const qreal dist = std::hypot(p.x - p.centerX, p.y - p.centerY);
        if (dist > p.moveRadius) {
            const qreal angle = std::atan2(p.y - p.centerY, p.x - p.centerX);
            p.dx -= std::cos(angle) * 0.5;
            p.dy -= std::sin(angle) * 0.5;
        }
    }
}

void ConnectionsEffectItem::advance()
{
    const qint64 now = m_clock.nsecsElapsed();
    qreal dtMs = (now - m_lastNs) / 1.0e6;
    m_lastNs = now;
    dtMs = qBound<qreal>(0.0, dtMs, kMaxFrameMs);

    m_accumMs += dtMs;
    while (m_accumMs >= kStepMs) {
        stepSimulation();
        m_accumMs -= kStepMs;
    }
    m_alpha = m_accumMs / kStepMs;
    update();
}

void ConnectionsEffectItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        recomputeDerivedParams();
        initPoints();
        update();
        // El driver solo arranca con width/height > 0; si el item entra a la
        // escena con tamano 0 (Loader, anchors) hay que reevaluarlo aqui.
        ensureDriverState();
    }
}

void ConnectionsEffectItem::ensureDriverState()
{
    const bool shouldRun = m_running && isVisible() && window()
                            && width() > 0 && height() > 0;
    if (shouldRun && m_driver->state() != QAbstractAnimation::Running) {
        m_lastNs = m_clock.nsecsElapsed();   // no acumular el tiempo que estuvo en pausa
        m_driver->start();
    } else if (!shouldRun && m_driver->state() == QAbstractAnimation::Running) {
        m_driver->stop();
    }
}

void ConnectionsEffectItem::itemChange(ItemChange change, const ItemChangeData &value)
{
    QQuickItem::itemChange(change, value);
    if (change == ItemVisibleHasChanged || change == ItemSceneChange) {
        ensureDriverState();
        if (m_points.isEmpty()) {
            initPoints();
        }
    }
}

QSGNode *ConnectionsEffectItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    if (m_points.isEmpty() && width() > 0 && height() > 0) {
        initPoints();
    }
    if (width() <= 0 || height() <= 0 || m_points.isEmpty()) {
        delete oldNode;
        return nullptr;
    }

    auto *root = oldNode;
    QSGGeometryNode *linesNode;
    QSGGeometryNode *pointsNode;

    if (!root) {
        root = new QSGNode();

        linesNode = new QSGGeometryNode();
        auto *lineGeometry = new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), 0);
        lineGeometry->setDrawingMode(QSGGeometry::DrawLines);
        lineGeometry->setLineWidth(1.0f);
        linesNode->setGeometry(lineGeometry);
        linesNode->setFlag(QSGNode::OwnsGeometry);
        linesNode->setMaterial(new QSGVertexColorMaterial());
        linesNode->setFlag(QSGNode::OwnsMaterial);
        root->appendChildNode(linesNode);

        pointsNode = new QSGGeometryNode();
        auto *pointGeometry = new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), 0);
        pointGeometry->setDrawingMode(QSGGeometry::DrawTriangles);
        pointsNode->setGeometry(pointGeometry);
        pointsNode->setFlag(QSGNode::OwnsGeometry);
        pointsNode->setMaterial(new QSGVertexColorMaterial());
        pointsNode->setFlag(QSGNode::OwnsMaterial);
        root->appendChildNode(pointsNode);
    } else {
        linesNode = static_cast<QSGGeometryNode *>(root->childAtIndex(0));
        pointsNode = static_cast<QSGGeometryNode *>(root->childAtIndex(1));
    }

    const QColor &lc = m_lineColor;
    const int cr = lc.red();
    const int cg = lc.green();
    const int cb = lc.blue();
    const int ca = lc.alpha();
    const qreal radius = m_pointSize / 2.0;
    const qreal halfPoint = radius;

    // ---- Posiciones interpoladas entre el paso anterior y el actual ----
    const int n = m_points.size();
    QVector<QPointF> pos(n);
    for (int i = 0; i < n; ++i) {
        const Point &p = m_points[i];
        pos[i] = QPointF(p.prevX + (p.x - p.prevX) * m_alpha,
                         p.prevY + (p.y - p.prevY) * m_alpha);
    }

    // ---- Puntos ----
    QSGGeometry *pointGeometry = pointsNode->geometry();
    const int segs = m_softEdges ? kSoftSegments : kHardSegments;
    const int vertsPerPoint = m_softEdges ? segs * 9 : segs * 3;   // soft: abanico + anillo
    const int neededPointVerts = n * vertsPerPoint;
    if (pointGeometry->vertexCount() != neededPointVerts) {
        pointGeometry->allocate(neededPointVerts);
    }
    auto *pv = pointGeometry->vertexDataAsColoredPoint2D();

    int vi = 0;
    const qreal rIn = qMax<qreal>(0.0, radius - 0.5);
    const qreal rOut = radius + 0.5;
    for (int i = 0; i < n; ++i) {
        const qreal cx = pos[i].x() + radius;
        const qreal cy = pos[i].y() + radius;
        for (int s = 0; s < segs; ++s) {
            const qreal a0 = (2.0 * M_PI * s) / segs;
            const qreal a1 = (2.0 * M_PI * (s + 1)) / segs;
            const qreal c0 = std::cos(a0), s0 = std::sin(a0);
            const qreal c1 = std::cos(a1), s1 = std::sin(a1);
            if (!m_softEdges) {
                setV(pv[vi++], cx, cy, cr, cg, cb, ca);
                setV(pv[vi++], cx + c0 * radius, cy + s0 * radius, cr, cg, cb, ca);
                setV(pv[vi++], cx + c1 * radius, cy + s1 * radius, cr, cg, cb, ca);
            } else {
                // abanico interior opaco
                setV(pv[vi++], cx, cy, cr, cg, cb, ca);
                setV(pv[vi++], cx + c0 * rIn, cy + s0 * rIn, cr, cg, cb, ca);
                setV(pv[vi++], cx + c1 * rIn, cy + s1 * rIn, cr, cg, cb, ca);
                // anillo exterior con alpha 0 (difuminado)
                setV(pv[vi++], cx + c0 * rIn,  cy + s0 * rIn,  cr, cg, cb, ca);
                setV(pv[vi++], cx + c0 * rOut, cy + s0 * rOut, cr, cg, cb, 0);
                setV(pv[vi++], cx + c1 * rIn,  cy + s1 * rIn,  cr, cg, cb, ca);
                setV(pv[vi++], cx + c1 * rIn,  cy + s1 * rIn,  cr, cg, cb, ca);
                setV(pv[vi++], cx + c0 * rOut, cy + s0 * rOut, cr, cg, cb, 0);
                setV(pv[vi++], cx + c1 * rOut, cy + s1 * rOut, cr, cg, cb, 0);
            }
        }
    }
    pointsNode->markDirty(QSGNode::DirtyGeometry);

    // ---- Conexiones: grid espacial sobre las posiciones interpoladas ----
    QHash<qint64, QVector<int>> grid;
    grid.reserve(n);
    const qreal cellSize = qMax<qreal>(1.0, m_connectionThreshold);
    for (int i = 0; i < n; ++i) {
        const int cx = static_cast<int>(std::floor(pos[i].x() / cellSize));
        const int cy = static_cast<int>(std::floor(pos[i].y() / cellSize));
        grid[cellKey(cx, cy)].push_back(i);
    }

    static const int offsets[9][2] = {
        {-1, -1}, {-1, 0}, {-1, 1}, {0, -1}, {0, 0}, {0, 1}, {1, -1}, {1, 0}, {1, 1}
    };

    struct Segment { qreal x1, y1, x2, y2; int alpha; };
    QVector<Segment> segments;
    segments.reserve(static_cast<int>(m_maxConnections));

    QSet<quint64> processedPairs;
    int connectionCount = 0;

    for (int i = 0; i < n && connectionCount < m_maxConnections; ++i) {
        const QPointF &p = pos[i];
        const int cellX = static_cast<int>(std::floor(p.x() / cellSize));
        const int cellY = static_cast<int>(std::floor(p.y() / cellSize));

        for (int oi = 0; oi < 9 && connectionCount < m_maxConnections; ++oi) {
            const qint64 key = cellKey(cellX + offsets[oi][0], cellY + offsets[oi][1]);
            const auto it = grid.constFind(key);
            if (it == grid.constEnd()) continue;

            for (int j : it.value()) {
                if (j == i) continue;
                const quint64 pairKey = i < j
                    ? (static_cast<quint64>(i) << 32) | static_cast<quint32>(j)
                    : (static_cast<quint64>(j) << 32) | static_cast<quint32>(i);
                if (processedPairs.contains(pairKey)) continue;

                const QPointF &o = pos[j];
                const qreal d = std::hypot(p.x() - o.x(), p.y() - o.y());
                if (d < m_connectionThreshold) {
                    processedPairs.insert(pairKey);
                    const qreal alphaFactor = qMax(0.2, 1.0 - d / m_connectionThreshold);
                    segments.push_back({p.x() + halfPoint, p.y() + halfPoint,
                                         o.x() + halfPoint, o.y() + halfPoint,
                                         qBound(0, int(alphaFactor * ca), 255)});
                    ++connectionCount;
                    if (connectionCount >= m_maxConnections) break;
                }
            }
        }
    }

    QSGGeometry *lineGeometry = linesNode->geometry();
    const int vertsPerSegment = m_softEdges ? 12 : 2;
    lineGeometry->setDrawingMode(m_softEdges ? QSGGeometry::DrawTriangles : QSGGeometry::DrawLines);
    const int neededLineVerts = segments.size() * vertsPerSegment;
    if (lineGeometry->vertexCount() != neededLineVerts) {
        lineGeometry->allocate(neededLineVerts);
    }
    auto *lv = lineGeometry->vertexDataAsColoredPoint2D();
    int li = 0;
    for (const Segment &s : std::as_const(segments)) {
        if (!m_softEdges) {
            setV(lv[li++], s.x1, s.y1, cr, cg, cb, s.alpha);
            setV(lv[li++], s.x2, s.y2, cr, cg, cb, s.alpha);
            continue;
        }
        // Linea difuminada: cinta de 3 vertices por extremo (-1px, 0, +1px),
        // alpha completo en el centro y 0 en los bordes.
        const qreal dx = s.x2 - s.x1, dy = s.y2 - s.y1;
        const qreal len = std::hypot(dx, dy);
        const qreal nx = len > 1e-6 ? -dy / len : 0.0;
        const qreal ny = len > 1e-6 ?  dx / len : 0.0;
        const qreal w = 1.0;
        const qreal ax0 = s.x1 - nx * w, ay0 = s.y1 - ny * w;
        const qreal ax2 = s.x1 + nx * w, ay2 = s.y1 + ny * w;
        const qreal bx0 = s.x2 - nx * w, by0 = s.y2 - ny * w;
        const qreal bx2 = s.x2 + nx * w, by2 = s.y2 + ny * w;
        // cuadrilatero 1: A0 A1 / B0 B1
        setV(lv[li++], ax0, ay0, cr, cg, cb, 0);
        setV(lv[li++], bx0, by0, cr, cg, cb, 0);
        setV(lv[li++], s.x1, s.y1, cr, cg, cb, s.alpha);
        setV(lv[li++], s.x1, s.y1, cr, cg, cb, s.alpha);
        setV(lv[li++], bx0, by0, cr, cg, cb, 0);
        setV(lv[li++], s.x2, s.y2, cr, cg, cb, s.alpha);
        // cuadrilatero 2: A1 A2 / B1 B2
        setV(lv[li++], s.x1, s.y1, cr, cg, cb, s.alpha);
        setV(lv[li++], s.x2, s.y2, cr, cg, cb, s.alpha);
        setV(lv[li++], ax2, ay2, cr, cg, cb, 0);
        setV(lv[li++], ax2, ay2, cr, cg, cb, 0);
        setV(lv[li++], s.x2, s.y2, cr, cg, cb, s.alpha);
        setV(lv[li++], bx2, by2, cr, cg, cb, 0);
    }
    linesNode->markDirty(QSGNode::DirtyGeometry);

    return root;
}
