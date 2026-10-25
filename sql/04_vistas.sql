SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Script 04: Vistas
   ===================================================================== */
USE ASADA;
GO

-- Vista de apoyo: abonados físicos y jurídicos en un mismo formato.
CREATE OR ALTER VIEW dbo.vw_Abonados
AS
SELECT
    'FISICO'                                         AS tipo_abonado,
    f.id_abonado_fisico                              AS id_abonado,
    f.tipo_identificacion,
    f.numero_identidad                               AS identificacion,
    CONCAT_WS(' ', f.nombre, f.apellido1, f.apellido2) AS nombre_completo,
    f.direccion, f.telefono, f.correo_electronico, f.fecha_registro, f.activo
FROM dbo.Abonado_Fisico f
UNION ALL
SELECT
    'JURIDICO',
    j.id_abonado_juridico,
    'JURIDICA',
    j.cedula_juridica,
    j.razon_social,
    j.direccion, j.telefono, j.correo_electronico, j.fecha_registro, j.activo
FROM dbo.Abonado_Juridico j;
GO

-- Saldo de cada factura (total + recargos aplicados - pagos aplicados).
CREATE OR ALTER VIEW dbo.vw_SaldoFactura
AS
SELECT
    f.id_factura,
    f.id_lectura,
    m.id_conexion,
    f.fecha_emision,
    f.fecha_vencimiento,
    f.monto_total,
    ISNULL(r.recargos, 0) AS recargos,
    ISNULL(p.pagado, 0)   AS pagado,
    f.monto_total + ISNULL(r.recargos, 0) - ISNULL(p.pagado, 0) AS saldo,
    f.estado
FROM dbo.Factura f
JOIN dbo.Lectura l ON l.id_lectura = f.id_lectura
JOIN dbo.Medidor m ON m.id_medidor = l.id_medidor
OUTER APPLY (SELECT SUM(rm.monto_recargo) AS recargos FROM dbo.Recargo_mora rm
             WHERE rm.id_factura = f.id_factura AND rm.estado = 'Aplicado') r
OUTER APPLY (SELECT SUM(pg.monto) AS pagado FROM dbo.Pago pg
             WHERE pg.id_factura = f.id_factura AND pg.estado = 'Aplicado') p;
GO

-- 12.5 Facturas pendientes de pago (pendientes o vencidas con saldo)
CREATE OR ALTER VIEW dbo.vw_FacturasPendientes
AS
SELECT
    s.id_factura, s.id_conexion,
    a.tipo_abonado, a.identificacion, a.nombre_completo,
    s.fecha_emision, s.fecha_vencimiento,
    s.monto_total, s.recargos, s.pagado, s.saldo, s.estado,
    CASE WHEN s.fecha_vencimiento < CAST(GETDATE() AS date)
         THEN DATEDIFF(DAY, s.fecha_vencimiento, GETDATE()) ELSE 0 END AS dias_atraso
FROM dbo.vw_SaldoFactura s
JOIN dbo.Conexion c ON c.id_conexion = s.id_conexion
JOIN dbo.vw_Abonados a
  ON (a.tipo_abonado = 'FISICO'   AND a.id_abonado = c.id_abonado_fisico)
  OR (a.tipo_abonado = 'JURIDICO' AND a.id_abonado = c.id_abonado_juridico)
WHERE s.estado IN ('Pendiente', 'Vencida') AND s.saldo > 0;
GO

-- 12.1 / 12.5 Abonados en estado de morosidad
CREATE OR ALTER VIEW dbo.vw_UsuariosMorosos
AS
SELECT
    tipo_abonado, identificacion, nombre_completo, id_conexion,
    COUNT(*)          AS cantidad_facturas_vencidas,
    SUM(saldo)        AS saldo_vencido,
    MIN(fecha_vencimiento) AS vencimiento_mas_antiguo,
    MAX(dias_atraso)  AS dias_atraso_maximo
FROM dbo.vw_FacturasPendientes
WHERE fecha_vencimiento < CAST(GETDATE() AS date)
GROUP BY tipo_abonado, identificacion, nombre_completo, id_conexion;
GO

-- 12.3 Medidores activos sin lectura en el mes actual
CREATE OR ALTER VIEW dbo.vw_MedidorNoLeido
AS
SELECT
    m.id_medidor, m.numero_serie, m.id_conexion, c.ubicacion,
    m.fecha_ultima_lectura,
    DATEDIFF(DAY, m.fecha_ultima_lectura, GETDATE()) AS dias_sin_lectura
FROM dbo.Medidor m
JOIN dbo.Conexion c ON c.id_conexion = m.id_conexion
WHERE m.estado = 'Activo'
  AND c.estado = 'Activa'
  AND NOT EXISTS (
        SELECT 1 FROM dbo.Lectura l
        WHERE l.id_medidor = m.id_medidor
          AND l.fecha_lectura_actual >= DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
  );
GO

-- 12.4 / 12.10 Resumen de consumo mensual por conexión (fuente del ETL)
CREATE OR ALTER VIEW dbo.vw_ResumenConsumoMensual
AS
SELECT
    YEAR(l.fecha_lectura_actual) * 100 + MONTH(l.fecha_lectura_actual) AS periodo,
    c.id_conexion,
    c.id_abonado_fisico,
    c.id_abonado_juridico,
    dbo.fn_ObtenerNombreCompleto(c.id_abonado_fisico, c.id_abonado_juridico) AS abonado,
    c.id_tarifa,
    tt.nombre_tarifa AS tipo_tarifa,
    COUNT(*)          AS cantidad_lecturas,
    SUM(l.consumo)    AS consumo_m3
FROM dbo.Lectura l
JOIN dbo.Medidor     m  ON m.id_medidor = l.id_medidor
JOIN dbo.Conexion    c  ON c.id_conexion = m.id_conexion
JOIN dbo.Tarifa      t  ON t.id_tarifa = c.id_tarifa
JOIN dbo.Tipo_Tarifa tt ON tt.id_tipo_tarifa = t.id_tipo_tarifa
GROUP BY YEAR(l.fecha_lectura_actual) * 100 + MONTH(l.fecha_lectura_actual),
         c.id_conexion, c.id_abonado_fisico, c.id_abonado_juridico, c.id_tarifa, tt.nombre_tarifa;
GO

-- 12.6 Total recaudado por método de pago
CREATE OR ALTER VIEW dbo.vw_PagosPorMetodo
AS
SELECT
    mp.id_metodo_pago, mp.nombre_metodo,
    COUNT(p.id_pago)        AS cantidad_pagos,
    ISNULL(SUM(p.monto), 0) AS total_recaudado
FROM dbo.Metodo_Pago mp
LEFT JOIN dbo.Pago p ON p.id_metodo_pago = mp.id_metodo_pago AND p.estado = 'Aplicado'
GROUP BY mp.id_metodo_pago, mp.nombre_metodo;
GO

-- 12.7 Incidentes pendientes de atención
CREATE OR ALTER VIEW dbo.vw_IncidentesAbiertos
AS
SELECT
    i.id_incidencia, ti.nombre_incidencia AS tipo, i.prioridad, i.estado,
    i.fecha_incidente, DATEDIFF(HOUR, i.fecha_incidente, GETDATE()) AS horas_abierta,
    i.descripcion, i.ubicacion, m.numero_serie AS medidor, m.id_conexion
FROM dbo.Incidencia i
JOIN dbo.Tipo_Incidencia ti ON ti.id_tipo_incidencia = i.id_tipo_incidencia
JOIN dbo.Medidor m          ON m.id_medidor = i.id_medidor
WHERE i.estado IN ('Abierta', 'En proceso');
GO

-- 12.9 Acciones registradas en los últimos 7 días
CREATE OR ALTER VIEW dbo.vw_BitacoraReciente
AS
SELECT
    b.id_bitacora, b.fecha_registro, b.accion, b.tabla_afectada, b.descripcion,
    b.id_usuario_sistema, ISNULL(u.nombre_usuario, 'SISTEMA') AS usuario
FROM dbo.Bitacora b
LEFT JOIN dbo.Usuario_Sistema u ON u.id_usuario_sistema = b.id_usuario_sistema
WHERE b.fecha_registro >= DATEADD(DAY, -7, GETDATE());
GO

-- 12.11 Alertas de consumo pendientes de revisión
CREATE OR ALTER VIEW dbo.vw_AlertasActivas
AS
SELECT
    a.id_alerta, n.nombre_nivel AS nivel, r.nombre_regla,
    m.numero_serie AS medidor, m.id_conexion,
    a.consumo_promedio, a.consumo_actual, a.porcentaje_variacion,
    a.fecha_deteccion, a.id_incidencia, a.observacion
FROM dbo.Alerta_Consumo a
JOIN dbo.Regla_consumo        r ON r.id_regla_consumo = a.id_regla_consumo
JOIN dbo.Nivel_alerta_Consumo n ON n.id_nivel_alerta = r.id_nivel_alerta
JOIN dbo.Lectura              l ON l.id_lectura = a.id_lectura
JOIN dbo.Medidor              m ON m.id_medidor = l.id_medidor
WHERE a.estado = 'Abierta';
GO

-- 12.13 Tarifas vigentes para facturación
CREATE OR ALTER VIEW dbo.vw_TarifasActivas
AS
SELECT t.id_tarifa, tt.id_tipo_tarifa, tt.nombre_tarifa AS tipo_tarifa, t.monto_fijo, t.monto_por_m3
FROM dbo.Tarifa t
JOIN dbo.Tipo_Tarifa tt ON tt.id_tipo_tarifa = t.id_tipo_tarifa
WHERE t.activo = 1 AND tt.activo = 1;
GO

-- 12.15 Recargos aplicados cuya factura todavía no está pagada
CREATE OR ALTER VIEW dbo.vw_RecargosPendientes
AS
SELECT
    r.id_recargo, r.id_factura, r.fecha_calculo, r.porcentaje_aplicado, r.monto_recargo,
    s.saldo AS saldo_factura, s.fecha_vencimiento, s.id_conexion
FROM dbo.Recargo_mora r
JOIN dbo.vw_SaldoFactura s ON s.id_factura = r.id_factura
WHERE r.estado = 'Aplicado' AND s.estado <> 'Pagada';
GO

-- 12.19 Mantenimientos abiertos o en proceso
CREATE OR ALTER VIEW dbo.vw_MantenimientosPendientes
AS
SELECT
    mt.id_mantenimiento, mt.estado, tt.nombre_trabajo AS tipo_trabajo,
    CONCAT_WS(' ', e.nombre_empleado, e.apellido1_empleado) AS responsable,
    mt.id_conexion, c.ubicacion, mt.id_incidencia, mt.descripcion, mt.fecha_inicio
FROM dbo.Mantenimiento mt
JOIN dbo.Tipo_Trabajo tt ON tt.id_tipo_trabajo = mt.id_tipo_trabajo
JOIN dbo.Empleado     e  ON e.id_empleado = mt.id_empleado
JOIN dbo.Conexion     c  ON c.id_conexion = mt.id_conexion
WHERE mt.estado IN ('Programado', 'En proceso');
GO

-- 12.21 Métodos de pago habilitados
CREATE OR ALTER VIEW dbo.vw_MetodosPagoActivos
AS
SELECT id_metodo_pago, nombre_metodo FROM dbo.Metodo_Pago WHERE activo = 1;
GO

-- 12.24 Usuarios habilitados para iniciar sesión
CREATE OR ALTER VIEW dbo.vw_UsuariosActivos
AS
SELECT
    u.id_usuario_sistema, u.nombre_usuario, r.nombre_rol,
    CONCAT_WS(' ', e.nombre_empleado, e.apellido1_empleado, e.apellido2_empleado) AS empleado,
    u.fecha_ultimo_acceso
FROM dbo.Usuario_Sistema u
JOIN dbo.Rol      r ON r.id_rol = u.id_rol
JOIN dbo.Empleado e ON e.id_empleado = u.id_empleado
WHERE u.activo = 1 AND e.activo = 1;
GO

-- 12.24 Cuentas bloqueadas por exceso de intentos fallidos (máximo: 3)
CREATE OR ALTER VIEW dbo.vw_UsuariosBloqueadosPorIntentos
AS
SELECT u.id_usuario_sistema, u.nombre_usuario, r.nombre_rol, u.intentos_fallidos, u.fecha_ultimo_acceso
FROM dbo.Usuario_Sistema u
JOIN dbo.Rol r ON r.id_rol = u.id_rol
WHERE u.activo = 0 AND u.intentos_fallidos >= 3;
GO

-- 12.31 Carga más reciente de cada tabla del Data Warehouse
CREATE OR ALTER VIEW dbo.vw_UltimaCargaPorTabla
AS
SELECT nombre_tabla_destino, fecha_proceso, fecha_ultima_carga, filas_procesadas, estado, mensaje_error
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY nombre_tabla_destino ORDER BY fecha_proceso DESC, id_proceso_etl DESC) AS rn
    FROM dbo.Control_ETL
) x
WHERE rn = 1;
GO

-- 12.31 Cargas fallidas que aún no se han reintentado
CREATE OR ALTER VIEW dbo.vw_CargasFallidas
AS
SELECT id_proceso_etl, nombre_tabla_destino, fecha_proceso, mensaje_error
FROM dbo.Control_ETL
WHERE estado = 'Fallido' AND reintentado = 0;
GO
