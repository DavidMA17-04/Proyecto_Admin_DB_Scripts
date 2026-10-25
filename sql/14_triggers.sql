SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Script 14: Triggers
   - El usuario que hace el cambio se toma de SESSION_CONTEXT
     (dbo.fn_UsuarioActual / dbo.fn_EmpleadoActual), que llena sp_IniciarSesion.
   - El comentario o motivo opcional que envían los procedimientos se lee de
     SESSION_CONTEXT(N'comentario').
   - Todos los triggers manejan inserciones o actualizaciones de varias filas.
   ===================================================================== */
USE ASADA;
GO

/* ---------------------------------------------------------------------
   12.1 Abonado: alta, modificación o baja
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_AuditoriaUsuario
ON dbo.Abonado_Fisico
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(),
           CASE WHEN d.id_abonado_fisico IS NULL THEN 'INSERT'
                WHEN i.id_abonado_fisico IS NULL THEN 'DELETE'
                ELSE 'UPDATE' END,
           'Abonado_Fisico',
           CASE
             WHEN d.id_abonado_fisico IS NULL THEN CONCAT('Alta del abonado físico ', i.id_abonado_fisico, ' (', i.numero_identidad, ' - ', i.nombre, ' ', i.apellido1, ').')
             WHEN i.id_abonado_fisico IS NULL THEN CONCAT('Eliminación física del abonado ', d.id_abonado_fisico, ' (', d.numero_identidad, ').')
             ELSE CONCAT('Modificación del abonado físico ', i.id_abonado_fisico, ':',
                    IIF(ISNULL(d.direccion, '') <> ISNULL(i.direccion, ''), CONCAT(' dirección [', d.direccion, ' -> ', i.direccion, ']'), ''),
                    IIF(ISNULL(d.telefono, '') <> ISNULL(i.telefono, ''), CONCAT(' teléfono [', d.telefono, ' -> ', i.telefono, ']'), ''),
                    IIF(ISNULL(d.correo_electronico, '') <> ISNULL(i.correo_electronico, ''), CONCAT(' correo [', d.correo_electronico, ' -> ', i.correo_electronico, ']'), ''),
                    IIF(CONCAT(d.nombre, d.apellido1, d.apellido2) <> CONCAT(i.nombre, i.apellido1, i.apellido2), ' nombre', ''),
                    IIF(d.activo <> i.activo, IIF(i.activo = 1, ' reactivado', ' desactivado (baja lógica)'), ''))
           END
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.id_abonado_fisico = i.id_abonado_fisico;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_AuditoriaUsuarioJuridico
ON dbo.Abonado_Juridico
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(),
           CASE WHEN d.id_abonado_juridico IS NULL THEN 'INSERT'
                WHEN i.id_abonado_juridico IS NULL THEN 'DELETE'
                ELSE 'UPDATE' END,
           'Abonado_Juridico',
           CASE
             WHEN d.id_abonado_juridico IS NULL THEN CONCAT('Alta del abonado jurídico ', i.id_abonado_juridico, ' (', i.cedula_juridica, ' - ', i.razon_social, ').')
             WHEN i.id_abonado_juridico IS NULL THEN CONCAT('Eliminación física del abonado jurídico ', d.id_abonado_juridico, ' (', d.cedula_juridica, ').')
             ELSE CONCAT('Modificación del abonado jurídico ', i.id_abonado_juridico, ':',
                    IIF(ISNULL(d.direccion, '') <> ISNULL(i.direccion, ''), CONCAT(' dirección [', d.direccion, ' -> ', i.direccion, ']'), ''),
                    IIF(ISNULL(d.telefono, '') <> ISNULL(i.telefono, ''), CONCAT(' teléfono [', d.telefono, ' -> ', i.telefono, ']'), ''),
                    IIF(ISNULL(d.correo_electronico, '') <> ISNULL(i.correo_electronico, ''), CONCAT(' correo [', d.correo_electronico, ' -> ', i.correo_electronico, ']'), ''),
                    IIF(d.razon_social <> i.razon_social, ' razón social', ''),
                    IIF(d.cedula_representante <> i.cedula_representante, ' representante legal', ''),
                    IIF(d.activo <> i.activo, IIF(i.activo = 1, ' reactivado', ' desactivado (baja lógica)'), ''))
           END
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.id_abonado_juridico = i.id_abonado_juridico;
END;
GO

/* ---------------------------------------------------------------------
   12.2 Conexión: alta, cambios de estado y de tarifa
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_AuditarConexion
ON dbo.Conexion
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    DECLARE @comentario varchar(4000) = CAST(SESSION_CONTEXT(N'comentario') AS varchar(4000));

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(),
           IIF(d.id_conexion IS NULL, 'INSERT', 'UPDATE'),
           'Conexion',
           CONCAT(
             IIF(d.id_conexion IS NULL,
                 CONCAT('Alta de la conexión ', i.id_conexion, ' en ', i.ubicacion, ' con tarifa ', i.id_tarifa, '.'),
                 CONCAT('Conexión ', i.id_conexion, ':',
                        IIF(d.estado <> i.estado, CONCAT(' estado [', d.estado, ' -> ', i.estado, ']'), ''),
                        IIF(d.id_tarifa <> i.id_tarifa, CONCAT(' tarifa [', d.id_tarifa, ' -> ', i.id_tarifa, ']'), ''),
                        IIF(d.ubicacion <> i.ubicacion, CONCAT(' ubicación [', d.ubicacion, ' -> ', i.ubicacion, ']'), ''))),
             IIF(@comentario IS NULL, '', CONCAT(' Motivo: ', @comentario)))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_conexion = i.id_conexion
    WHERE d.id_conexion IS NULL
       OR d.estado <> i.estado OR d.id_tarifa <> i.id_tarifa OR d.ubicacion <> i.ubicacion;
END;
GO

/* ---------------------------------------------------------------------
   12.3 Medidor
   --------------------------------------------------------------------- */
-- Registra el retiro (o daño/sustitución) del medidor sin borrar el registro.
CREATE OR ALTER TRIGGER dbo.trg_RetiroMedidor
ON dbo.Medidor
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    DECLARE @comentario varchar(4000) = CAST(SESSION_CONTEXT(N'comentario') AS varchar(4000));

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(),
           IIF(d.id_medidor IS NULL, 'INSERT', 'UPDATE'),
           'Medidor',
           CONCAT(IIF(d.id_medidor IS NULL,
                      CONCAT('Instalación del medidor ', i.numero_serie, ' en la conexión ', i.id_conexion, '.'),
                      CONCAT('Medidor ', i.numero_serie, ': estado [', d.estado, ' -> ', i.estado, ']',
                             IIF(i.estado = 'Retirado', ' (baja lógica, se conserva el historial de lecturas).', '.'))),
                  IIF(@comentario IS NULL, '', CONCAT(' Motivo: ', @comentario)))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_medidor = i.id_medidor
    WHERE d.id_medidor IS NULL OR d.estado <> i.estado;
END;
GO

-- Un medidor nunca se elimina físicamente: el DELETE se convierte en baja lógica.
CREATE OR ALTER TRIGGER dbo.trg_ImpedirEliminarMedidor
ON dbo.Medidor
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE m SET estado = 'Retirado'
    FROM dbo.Medidor m
    JOIN deleted d ON d.id_medidor = m.id_medidor
    WHERE m.estado <> 'Retirado';
END;
GO

/* ---------------------------------------------------------------------
   12.4 Lectura
   --------------------------------------------------------------------- */
-- Mantiene en Medidor la última lectura registrada.
CREATE OR ALTER TRIGGER dbo.trg_ActualizarUltimaLectura
ON dbo.Lectura
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    UPDATE m
    SET ultima_lectura = ul.lectura_actual,
        fecha_ultima_lectura = ul.fecha_lectura_actual
    FROM dbo.Medidor m
    JOIN (SELECT DISTINCT id_medidor FROM inserted) i ON i.id_medidor = m.id_medidor
    CROSS APPLY (SELECT TOP (1) l.lectura_actual, l.fecha_lectura_actual
                 FROM dbo.Lectura l
                 WHERE l.id_medidor = m.id_medidor
                 ORDER BY l.fecha_lectura_actual DESC, l.id_lectura DESC) ul;
END;
GO

-- Verifica anomalías de consumo para cada lectura nueva (R9).
CREATE OR ALTER TRIGGER dbo.trg_VerificarConsumoAlInsertar
ON dbo.Lectura
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id_lectura int;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT id_lectura FROM inserted ORDER BY id_lectura;

    OPEN cur;
    FETCH NEXT FROM cur INTO @id_lectura;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.sp_DetectarConsumoAnomalo @id_lectura = @id_lectura;
        FETCH NEXT FROM cur INTO @id_lectura;
    END
    CLOSE cur;
    DEALLOCATE cur;
END;
GO

-- R2-01: las correcciones de lecturas quedan en la bitácora.
CREATE OR ALTER TRIGGER dbo.trg_AuditarLectura
ON dbo.Lectura
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @comentario varchar(4000) = CAST(SESSION_CONTEXT(N'comentario') AS varchar(4000));

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), 'UPDATE', 'Lectura',
           CONCAT('Corrección de la lectura ', i.id_lectura, ' del medidor ', i.id_medidor,
                  ': [', d.lectura_actual, ' -> ', i.lectura_actual, ']',
                  IIF(@comentario IS NULL, '', CONCAT(' Motivo: ', @comentario)))
    FROM inserted i
    JOIN deleted d ON d.id_lectura = i.id_lectura
    WHERE d.lectura_actual <> i.lectura_actual OR d.lectura_anterior <> i.lectura_anterior;
END;
GO

/* ---------------------------------------------------------------------
   12.5 Factura
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_RegistroFactura
ON dbo.Factura
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), 'INSERT', 'Factura',
           CONCAT('Emisión de la factura ', i.id_factura, ' (lectura ', i.id_lectura, ') por ¢', FORMAT(i.monto_total, 'N2'),
                  ', vence el ', FORMAT(i.fecha_vencimiento, 'dd/MM/yyyy'), '.')
    FROM inserted i;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_AuditarFactura
ON dbo.Factura
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), 'UPDATE', 'Factura',
           CONCAT('Factura ', i.id_factura, ':',
                  IIF(d.estado <> i.estado, CONCAT(' estado [', d.estado, ' -> ', i.estado, ']'), ''),
                  IIF(d.fecha_vencimiento <> i.fecha_vencimiento,
                      CONCAT(' vencimiento [', FORMAT(d.fecha_vencimiento, 'dd/MM/yyyy'), ' -> ', FORMAT(i.fecha_vencimiento, 'dd/MM/yyyy'), ']'), ''))
    FROM inserted i
    JOIN deleted d ON d.id_factura = i.id_factura
    WHERE d.estado <> i.estado OR d.fecha_vencimiento <> i.fecha_vencimiento;
END;
GO

/* ---------------------------------------------------------------------
   12.6 Pago
   --------------------------------------------------------------------- */
-- Recalcula el estado de las facturas afectadas por un pago o su anulación:
-- saldo <= 0 -> Pagada; con saldo y vencida -> Vencida; con saldo y al día -> Pendiente.
CREATE OR ALTER TRIGGER dbo.trg_ActualizarEstadoFactura
ON dbo.Pago
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    UPDATE f
    SET estado = n.nuevo_estado, fecha_modificacion = GETDATE()
    FROM dbo.Factura f
    JOIN (SELECT DISTINCT id_factura FROM inserted) i ON i.id_factura = f.id_factura
    CROSS APPLY (SELECT CASE
                          WHEN dbo.fn_CalcularSaldoPendiente(f.id_factura) <= 0 THEN 'Pagada'
                          WHEN f.fecha_vencimiento < CAST(GETDATE() AS date)    THEN 'Vencida'
                          ELSE 'Pendiente'
                        END AS nuevo_estado) n
    WHERE f.estado <> n.nuevo_estado;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_AuditarPago
ON dbo.Pago
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(),
           IIF(d.id_pago IS NULL, 'INSERT', 'UPDATE'),
           'Pago',
           IIF(d.id_pago IS NULL,
               CONCAT('Pago ', i.id_pago, ' de ¢', FORMAT(i.monto, 'N2'), ' a la factura ', i.id_factura, ' (método ', i.id_metodo_pago, ').'),
               CONCAT('Pago ', i.id_pago, ': estado [', d.estado, ' -> ', i.estado, ']', IIF(i.motivo_anulacion IS NULL, '', CONCAT(' Motivo: ', i.motivo_anulacion))))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_pago = i.id_pago
    WHERE d.id_pago IS NULL OR d.estado <> i.estado;
END;
GO

/* ---------------------------------------------------------------------
   12.15 Recargo por mora
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_AuditarRecargoMora
ON dbo.Recargo_mora
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(),
           IIF(d.id_recargo IS NULL, 'INSERT', 'UPDATE'),
           'Recargo_mora',
           IIF(d.id_recargo IS NULL,
               CONCAT('Recargo ', i.id_recargo, ' de ', i.porcentaje_aplicado, '% (¢', FORMAT(i.monto_recargo, 'N2'), ') a la factura ', i.id_factura, '.'),
               CONCAT('Recargo ', i.id_recargo, ' anulado. Motivo: ', i.motivo_anulacion))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_recargo = i.id_recargo
    WHERE d.id_recargo IS NULL OR d.estado <> i.estado;
END;
GO

/* ---------------------------------------------------------------------
   12.7 / 12.30 Incidencia
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_IngresarIncidente
ON dbo.Incidencia
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), 'INSERT', 'Incidencia',
           CONCAT('Nueva incidencia ', i.id_incidencia, ' (prioridad ', i.prioridad, ') en el medidor ', i.id_medidor, ': ', i.descripcion)
    FROM inserted i;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_AuditarIncidente
ON dbo.Incidencia
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), 'UPDATE', 'Incidencia',
           CONCAT('Incidencia ', i.id_incidencia, ': estado [', d.estado, ' -> ', i.estado, ']')
    FROM inserted i
    JOIN deleted d ON d.id_incidencia = i.id_incidencia
    WHERE d.estado <> i.estado;
END;
GO

-- Guarda en Historial_Incidencia el estado inicial y cada cambio de estado.
CREATE OR ALTER TRIGGER dbo.trg_RegistrarHistorialIncidencia
ON dbo.Incidencia
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    INSERT INTO dbo.Historial_Incidencia (id_incidencia, id_empleado, estado_anterior, estado_actual, fecha_evento, observacion)
    SELECT i.id_incidencia, dbo.fn_EmpleadoActual(), d.estado, i.estado, GETDATE(),
           ISNULL(CAST(SESSION_CONTEXT(N'comentario') AS varchar(4000)), IIF(d.id_incidencia IS NULL, 'Incidencia registrada', NULL))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_incidencia = i.id_incidencia
    WHERE d.id_incidencia IS NULL OR d.estado <> i.estado;
END;
GO

/* ---------------------------------------------------------------------
   12.19 Mantenimiento
   --------------------------------------------------------------------- */
-- Registra en Historial_Mantenimiento la creación y cada cambio de estado.
CREATE OR ALTER TRIGGER dbo.trg_AuditarMantenimiento
ON dbo.Mantenimiento
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    DECLARE @comentario varchar(4000) = CAST(SESSION_CONTEXT(N'comentario') AS varchar(4000));

    INSERT INTO dbo.Historial_Mantenimiento (id_mantenimiento, id_empleado, estado_anterior, estado_actual, fecha_evento, anotacion)
    SELECT i.id_mantenimiento, ISNULL(dbo.fn_EmpleadoActual(), i.id_empleado), d.estado, i.estado, GETDATE(),
           ISNULL(@comentario, IIF(d.id_mantenimiento IS NULL, CONCAT('Programado: ', i.descripcion), NULL))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_mantenimiento = i.id_mantenimiento
    WHERE d.id_mantenimiento IS NULL OR d.estado <> i.estado;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), IIF(d.id_mantenimiento IS NULL, 'INSERT', 'UPDATE'), 'Mantenimiento',
           CONCAT('Mantenimiento ', i.id_mantenimiento, IIF(d.id_mantenimiento IS NULL, ' programado', CONCAT(': estado [', d.estado, ' -> ', i.estado, ']')),
                  ' (empleado ', i.id_empleado, ', conexión ', i.id_conexion, ').')
    FROM inserted i
    LEFT JOIN deleted d ON d.id_mantenimiento = i.id_mantenimiento
    WHERE d.id_mantenimiento IS NULL OR d.estado <> i.estado;
END;
GO

/* ---------------------------------------------------------------------
   12.8 Empleado
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_ActualizarEmpleado
ON dbo.Empleado
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), IIF(d.id_empleado IS NULL, 'INSERT', 'UPDATE'), 'Empleado',
           IIF(d.id_empleado IS NULL,
               CONCAT('Alta del empleado ', i.id_empleado, ' (', i.cedula, ' - ', i.nombre_empleado, ' ', i.apellido1_empleado, ', ', i.puesto, ').'),
               CONCAT('Empleado ', i.id_empleado, ':',
                      IIF(d.puesto <> i.puesto, CONCAT(' puesto [', d.puesto, ' -> ', i.puesto, ']'), ''),
                      IIF(d.activo <> i.activo, IIF(i.activo = 1, ' activado', ' desactivado'), ''),
                      IIF(d.cedula <> i.cedula, CONCAT(' cédula [', d.cedula, ' -> ', i.cedula, ']'), ''),
                      IIF(ISNULL(d.telefono, '') <> ISNULL(i.telefono, ''), ' teléfono', ''),
                      IIF(CONCAT(d.nombre_empleado, d.apellido1_empleado, d.apellido2_empleado) <>
                          CONCAT(i.nombre_empleado, i.apellido1_empleado, i.apellido2_empleado), ' nombre', '')))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_empleado = i.id_empleado;
END;
GO

/* ---------------------------------------------------------------------
   12.13 Tarifa: cada cambio de monto va a Historial_Tarifa y a la bitácora
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_AuditarTarifa
ON dbo.Tarifa
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    INSERT INTO dbo.Historial_Tarifa (id_tarifa, monto_fijo_anterior, monto_fijo_nuevo, monto_por_m3_anterior, monto_por_m3_nuevo, fecha_cambio, id_usuario_sistema)
    SELECT i.id_tarifa, d.monto_fijo, i.monto_fijo, d.monto_por_m3, i.monto_por_m3, GETDATE(), dbo.fn_UsuarioActual()
    FROM inserted i
    JOIN deleted d ON d.id_tarifa = i.id_tarifa
    WHERE d.monto_fijo <> i.monto_fijo OR d.monto_por_m3 <> i.monto_por_m3;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), IIF(d.id_tarifa IS NULL, 'INSERT', 'UPDATE'), 'Tarifa',
           IIF(d.id_tarifa IS NULL,
               CONCAT('Alta de la tarifa ', i.id_tarifa, ': fijo ¢', i.monto_fijo, ', m³ ¢', i.monto_por_m3, '.'),
               CONCAT('Tarifa ', i.id_tarifa, ':',
                      IIF(d.monto_fijo <> i.monto_fijo, CONCAT(' monto fijo [', d.monto_fijo, ' -> ', i.monto_fijo, ']'), ''),
                      IIF(d.monto_por_m3 <> i.monto_por_m3, CONCAT(' monto por m³ [', d.monto_por_m3, ' -> ', i.monto_por_m3, ']'), ''),
                      IIF(d.activo <> i.activo, IIF(i.activo = 1, ' activada', ' desactivada'), '')))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_tarifa = i.id_tarifa
    WHERE d.id_tarifa IS NULL OR d.monto_fijo <> i.monto_fijo OR d.monto_por_m3 <> i.monto_por_m3 OR d.activo <> i.activo;
END;
GO

/* ---------------------------------------------------------------------
   12.11 Alertas y reglas de consumo
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_AuditarAlertaConsumo
ON dbo.Alerta_Consumo
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), IIF(d.id_alerta IS NULL, 'INSERT', 'UPDATE'), 'Alerta_Consumo',
           IIF(d.id_alerta IS NULL,
               CONCAT('Alerta ', i.id_alerta, ' por consumo anómalo en la lectura ', i.id_lectura, ': ',
                      i.consumo_actual, ' m³ contra un promedio de ', i.consumo_promedio, ' m³ (',
                      ISNULL(CONCAT(i.porcentaje_variacion, '%'), 'sin promedio'), ').'),
               CONCAT('Alerta ', i.id_alerta, ':',
                      IIF(d.estado <> i.estado, CONCAT(' estado [', d.estado, ' -> ', i.estado, ']'), ''),
                      IIF(ISNULL(d.id_incidencia, 0) <> ISNULL(i.id_incidencia, 0), CONCAT(' vinculada a la incidencia ', i.id_incidencia), ''),
                      IIF(ISNULL(d.observacion, '') <> ISNULL(i.observacion, ''), ' observación actualizada', '')))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_alerta = i.id_alerta;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_AuditarReglaConsumo
ON dbo.Regla_consumo
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), IIF(d.id_regla_consumo IS NULL, 'INSERT', 'UPDATE'), 'Regla_consumo',
           CONCAT(IIF(d.id_regla_consumo IS NULL, 'Alta de la regla ', 'Modificación de la regla '), i.id_regla_consumo,
                  ' "', i.nombre_regla, '": variación ', i.porcentaje_variacion, '%, ', i.meses_promedio, ' meses, mínimo ',
                  i.consumo_minimo, ' m³, nivel ', i.id_nivel_alerta, IIF(i.activo = 1, ', activa.', ', inactiva.'))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_regla_consumo = i.id_regla_consumo;
END;
GO

/* ---------------------------------------------------------------------
   12.12 Respaldos
   --------------------------------------------------------------------- */
-- Si un respaldo queda como 'Fallido', genera una alerta en la bitácora.
-- Si quien ejecuta es sysadmin, también la escribe en el log de errores de SQL Server
-- (lo que permite configurar una alerta de SQL Agent por correo).
CREATE OR ALTER TRIGGER dbo.trg_RegistrarRespaldo
ON dbo.Historial_Respaldo
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted WHERE estado = 'Fallido') RETURN;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), 'ALERTA', 'Historial_Respaldo',
           CONCAT('Falló el respaldo ', i.id_respaldo, ' de la política ', i.id_politica, ': ', i.mensaje_error)
    FROM inserted i
    WHERE i.estado = 'Fallido';

    IF IS_SRVROLEMEMBER('sysadmin') = 1
        RAISERROR('ASADA: se registró un respaldo fallido. Revise Historial_Respaldo.', 10, 1) WITH LOG;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_AuditarPoliticaRespaldo
ON dbo.Politica_Respaldo
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), IIF(d.id_politica IS NULL, 'INSERT', 'UPDATE'), 'Politica_Respaldo',
           IIF(d.id_politica IS NULL,
               CONCAT('Alta de la política ', i.id_politica, ' "', i.nombre_politica, '" (', i.frecuencia, ' a las ',
                      CONVERT(varchar(5), i.hora_ejecucion, 108), ', retención ', i.retencion_dias, ' días, destino ', i.ruta_destino, ').'),
               CONCAT('Política ', i.id_politica, ':',
                      IIF(d.frecuencia <> i.frecuencia, CONCAT(' frecuencia [', d.frecuencia, ' -> ', i.frecuencia, ']'), ''),
                      IIF(d.hora_ejecucion <> i.hora_ejecucion, CONCAT(' hora [', CONVERT(varchar(5), d.hora_ejecucion, 108), ' -> ', CONVERT(varchar(5), i.hora_ejecucion, 108), ']'), ''),
                      IIF(d.retencion_dias <> i.retencion_dias, CONCAT(' retención [', d.retencion_dias, ' -> ', i.retencion_dias, ']'), ''),
                      IIF(d.ruta_destino <> i.ruta_destino, CONCAT(' destino [', d.ruta_destino, ' -> ', i.ruta_destino, ']'), ''),
                      IIF(d.activo <> i.activo, IIF(i.activo = 1, ' activada', ' desactivada'), '')))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_politica = i.id_politica;
END;
GO

/* ---------------------------------------------------------------------
   12.24 / 12.27 Seguridad
   --------------------------------------------------------------------- */
-- Nunca se escribe la contraseña ni su hash en la bitácora.
CREATE OR ALTER TRIGGER dbo.trg_AuditarUsuarioSistema
ON dbo.Usuario_Sistema
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), IIF(d.id_usuario_sistema IS NULL, 'INSERT', 'UPDATE'), 'Usuario_Sistema',
           IIF(d.id_usuario_sistema IS NULL,
               CONCAT('Alta del usuario "', i.nombre_usuario, '" (empleado ', i.id_empleado, ', rol ', i.id_rol, ').'),
               CONCAT('Usuario "', i.nombre_usuario, '":',
                      IIF(d.contrasena_usuario <> i.contrasena_usuario, ' cambio de contraseña', ''),
                      IIF(d.id_rol <> i.id_rol, CONCAT(' rol [', d.id_rol, ' -> ', i.id_rol, ']'), ''),
                      IIF(d.id_empleado <> i.id_empleado, CONCAT(' empleado [', d.id_empleado, ' -> ', i.id_empleado, ']'), ''),
                      IIF(d.activo = 1 AND i.activo = 0,
                          IIF(i.intentos_fallidos >= 3, ' bloqueado por intentos fallidos', ' desactivado'), ''),
                      IIF(d.activo = 0 AND i.activo = 1, ' reactivado', '')))
    FROM inserted i
    LEFT JOIN deleted d ON d.id_usuario_sistema = i.id_usuario_sistema
    -- No se registran los cambios que solo actualizan la fecha de acceso o el contador de intentos.
    WHERE d.id_usuario_sistema IS NULL
       OR d.contrasena_usuario <> i.contrasena_usuario OR d.id_rol <> i.id_rol
       OR d.id_empleado <> i.id_empleado OR d.activo <> i.activo;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_AuditarRolPermiso
ON dbo.Rol_permiso
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), 'INSERT', 'Rol_permiso',
           CONCAT('Se asignó el permiso "', p.nombre_permiso, '" al rol "', r.nombre_rol, '".')
    FROM inserted i
    JOIN dbo.Rol r     ON r.id_rol = i.id_rol
    JOIN dbo.Permiso p ON p.id_permiso = i.id_permiso;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), 'DELETE', 'Rol_permiso',
           CONCAT('Se quitó el permiso "', p.nombre_permiso, '" al rol "', r.nombre_rol, '".')
    FROM deleted d
    JOIN dbo.Rol r     ON r.id_rol = d.id_rol
    JOIN dbo.Permiso p ON p.id_permiso = d.id_permiso;
END;
GO

/* ---------------------------------------------------------------------
   12.31 Control ETL
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_AlertarFalloETL
ON dbo.Control_ETL
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
    SELECT dbo.fn_UsuarioActual(), 'ALERTA', 'Control_ETL',
           CONCAT('Falló la carga ETL ', i.id_proceso_etl, ' hacia ', i.nombre_tabla_destino, ': ', i.mensaje_error)
    FROM inserted i
    LEFT JOIN deleted d ON d.id_proceso_etl = i.id_proceso_etl
    WHERE i.estado = 'Fallido' AND (d.id_proceso_etl IS NULL OR d.estado <> 'Fallido');
END;
GO
