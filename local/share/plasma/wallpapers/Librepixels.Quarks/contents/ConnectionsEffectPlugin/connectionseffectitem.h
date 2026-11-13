#pragma once

#include <QQuickItem>
#include <QColor>
#include <QElapsedTimer>
#include <QVector>
#include <qqmlregistration.h>

/**
 * ConnectionsEffectItem
 *
 * Efecto "puntos + conexiones" dibujado directamente en el scene graph.
 *
 * Cambios respecto a la primera version:
 *  - La simulacion avanza con el driver de animaciones de Qt Quick (el mismo
 *    que usa el Timer de QML), sincronizado con el vsync, en pasos fijos de
 *    1/60 s con interpolacion entre pasos: movimiento fluido a cualquier
 *    frecuencia de refresco.
 *  - Los colores se envian premultiplicados (lo que espera QSGVertexColorMaterial).
 *  - softEdges: bordes suavizados (antialiasing) en lineas y puntos.
 */
class ConnectionsEffectItem : public QQuickItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(ConnectionsEffect)
    QML_ADDED_IN_VERSION(1, 0)

    Q_PROPERTY(qreal level READ level WRITE setLevel NOTIFY levelChanged)
    Q_PROPERTY(int connectionsLevel READ connectionsLevel WRITE setConnectionsLevel NOTIFY connectionsLevelChanged)
    Q_PROPERTY(QColor lineColor READ lineColor WRITE setLineColor NOTIFY lineColorChanged)
    Q_PROPERTY(qreal pointSize READ pointSize WRITE setPointSize NOTIFY pointSizeChanged)
    Q_PROPERTY(qreal animationSpeed READ animationSpeed WRITE setAnimationSpeed NOTIFY animationSpeedChanged)
    Q_PROPERTY(bool running READ isRunning WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(bool softEdges READ softEdges WRITE setSoftEdges NOTIFY softEdgesChanged)
    // Distancia maxima (px) a la que dos puntos se conectan. 0 = automatico (segun connectionsLevel).
    Q_PROPERTY(qreal connectionThreshold READ connectionThreshold WRITE setConnectionThreshold NOTIFY connectionThresholdChanged)
    // Tope de conexiones = puntos * connectionsFactor. 0 = automatico (segun connectionsLevel).
    Q_PROPERTY(qreal connectionsFactor READ connectionsFactor WRITE setConnectionsFactor NOTIFY connectionsFactorChanged)
    Q_PROPERTY(int pointCount READ pointCount NOTIFY pointCountChanged)

public:
    explicit ConnectionsEffectItem(QQuickItem *parent = nullptr);
    ~ConnectionsEffectItem() override;

    qreal level() const { return m_level; }
    void setLevel(qreal l);

    int connectionsLevel() const { return m_connectionsLevel; }
    void setConnectionsLevel(int l);

    QColor lineColor() const { return m_lineColor; }
    void setLineColor(const QColor &c);

    qreal pointSize() const { return m_pointSize; }
    void setPointSize(qreal s);

    qreal animationSpeed() const { return m_animationSpeed; }
    void setAnimationSpeed(qreal s);

    bool isRunning() const { return m_running; }
    void setRunning(bool r);

    bool softEdges() const { return m_softEdges; }
    void setSoftEdges(bool s);

    qreal connectionThreshold() const { return m_thresholdOverride; }
    void setConnectionThreshold(qreal t);

    qreal connectionsFactor() const { return m_factorOverride; }
    void setConnectionsFactor(qreal f);

    int pointCount() const { return m_points.size(); }

signals:
    void levelChanged();
    void connectionsLevelChanged();
    void lineColorChanged();
    void pointSizeChanged();
    void animationSpeedChanged();
    void runningChanged();
    void softEdgesChanged();
    void connectionThresholdChanged();
    void connectionsFactorChanged();
    void pointCountChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private:
    class FrameDriver;
    friend class FrameDriver;

    struct Point {
        qreal x = 0, y = 0;
        qreal prevX = 0, prevY = 0;   // posicion en el paso anterior (para interpolar)
        qreal dx = 0, dy = 0;
        qreal centerX = 0, centerY = 0;
        qreal moveRadius = 0;
    };

    void recomputeDerivedParams();
    void initPoints();
    void stepSimulation();
    void advance();            // llamado una vez por frame por el driver de animaciones
    void ensureDriverState();

    qreal m_level = 1.0;
    int m_connectionsLevel = 2;
    QColor m_lineColor = QColor("white");
    qreal m_pointSize = 2.0;
    qreal m_animationSpeed = 0.6;
    bool m_running = true;
    bool m_softEdges = true;
    qreal m_thresholdOverride = 0.0;   // 0 = automatico
    qreal m_factorOverride = 0.0;      // 0 = automatico

    qreal m_density = 0.3;
    int m_numPoints = 0;
    qreal m_connectionThreshold = 40.0;
    qreal m_maxConnections = 0;

    static constexpr qreal kMovementRangeMin = 0.15;
    static constexpr qreal kMovementRangeMax = 0.38;
    static constexpr qreal kMargin = 12.0;

    QVector<Point> m_points;

    FrameDriver *m_driver = nullptr;
    QElapsedTimer m_clock;
    qint64 m_lastNs = 0;
    qreal m_accumMs = 0.0;
    qreal m_alpha = 1.0;       // fraccion [0,1] entre el paso anterior y el actual
};
