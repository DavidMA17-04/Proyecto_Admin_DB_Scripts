SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Script 08: Procedimientos - Incidencias, mantenimientos y empleados 
  --------------------------------------------------------------------*/
USE ASADA;
GO

   --Incidencia
-- Registra una incidencia. Si viene de una alerta de consumo, la vincula.
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarIncidente
    @id_medidor          int,
    @id_tipo_incidencia  int,
    @descripcion         varchar(100),
    @ubicacion           varchar(20) = NULL,
    @fecha_incidente     datetime    = NULL,
    @id_alerta           int         = NULL,
    @id_incidencia       int         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Medidor WHERE id_medidor = @id_medidor)
        THROW 50401, 'El medidor indicado no existe.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Tipo_Incidencia WHERE id_tipo_incidencia = @id_tipo_incidencia AND activo = 1)
        THROW 50402, 'El tipo de incidencia no existe o está inactivo.', 1;

    IF NULLIF(LTRIM(@descripcion), '') IS NULL
        THROW 50403, 'Debe describir la incidencia.', 1;

    IF @id_alerta IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Alerta_Consumo WHERE id_alerta = @id_alerta)
        THROW 50404, 'La alerta de consumo indicada no existe.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.Incidencia (id_medidor, id_tipo_incidencia, fecha_incidente, descripcion, ubicacion, prioridad, fecha_modificacion)
        VALUES (@id_medidor, @id_tipo_incidencia, ISNULL(@fecha_incidente, GETDATE()), @descripcion, @ubicacion,
                dbo.fn_ClasificarIncidencia(@descripcion, @id_tipo_incidencia), GETDATE());

        SET @id_incidencia = SCOPE_IDENTITY();

        IF @id_alerta IS NOT NULL
            UPDATE dbo.Alerta_Consumo SET id_incidencia = @id_incidencia WHERE id_alerta = @id_alerta;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

-- Cambia el estado de una incidencia. trg_RegistrarHistorialIncidencia guarda
-- el cambio en Historial_Incidencia junto con la observación.
CREATE OR ALTER PROCEDURE dbo.sp_CambiarEstadoIncidencia
    @id_incidencia int,
    @nuevo_estado  varchar(20),
    @observacion   varchar(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado_actual varchar(20);
    SELECT @estado_actual = estado FROM dbo.Incidencia WHERE id_incidencia = @id_incidencia;

    IF @estado_actual IS NULL
        THROW 50405, 'La incidencia indicada no existe.', 1;

    IF @nuevo_estado NOT IN ('Abierta', 'En proceso', 'Resuelta')
        THROW 50406, 'Estado no válido. Use: Abierta, En proceso o Resuelta.', 1;

    IF @estado_actual = @nuevo_estado
        THROW 50407, 'La incidencia ya se encuentra en ese estado.', 1;

    EXEC sys.sp_set_session_context @key = N'comentario', @value = @observacion;

    UPDATE dbo.Incidencia
    SET estado = @nuevo_estado, fecha_modificacion = GETDATE()
    WHERE id_incidencia = @id_incidencia;

    EXEC sys.sp_set_session_context @key = N'comentario', @value = NULL;
END;
GO

-- Cierra una incidencia registrando la solución aplicada.
CREATE OR ALTER PROCEDURE dbo.sp_CerrarIncidente
    @id_incidencia int,
    @solucion      varchar(4000)
AS
BEGIN
    SET NOCOUNT ON;

    IF NULLIF(LTRIM(@solucion), '') IS NULL
        THROW 50408, 'Debe indicar la solución aplicada.', 1;

    EXEC dbo.sp_CambiarEstadoIncidencia
        @id_incidencia = @id_incidencia,
        @nuevo_estado  = 'Resuelta',
        @observacion   = @solucion;
END;
GO

-- Convierte una incidencia abierta en un mantenimiento y la pasa a 'En proceso'.
CREATE OR ALTER PROCEDURE dbo.sp_AsignarMantenimiento
    @id_incidencia     int,
    @id_empleado       int,
    @id_tipo_trabajo   int,
    @descripcion       varchar(100) = NULL,
    @fecha_inicio      datetime     = NULL,
    @id_mantenimiento  int          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado varchar(20), @id_conexion int, @desc_incidencia varchar(100);

    SELECT @estado = i.estado, @id_conexion = m.id_conexion, @desc_incidencia = i.descripcion
    FROM dbo.Incidencia i
    JOIN dbo.Medidor m ON m.id_medidor = i.id_medidor
    WHERE i.id_incidencia = @id_incidencia;

    IF @estado IS NULL
        THROW 50405, 'La incidencia indicada no existe.', 1;

    IF @estado = 'Resuelta'
        THROW 50409, 'La incidencia ya está resuelta.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC dbo.sp_ProgramarMantenimiento
            @id_empleado      = @id_empleado,
            @id_tipo_trabajo  = @id_tipo_trabajo,
            @id_conexion      = @id_conexion,
            @descripcion      = @descripcion,
            @id_incidencia    = @id_incidencia,
            @fecha_inicio     = @fecha_inicio,
            @id_mantenimiento = @id_mantenimiento OUTPUT;

        IF @estado = 'Abierta'
            EXEC dbo.sp_CambiarEstadoIncidencia
                @id_incidencia = @id_incidencia,
                @nuevo_estado  = 'En proceso',
                @observacion   = 'Mantenimiento asignado';

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

--búsqueda de incidencias por estado, tipo, conexión o rango de fechas.
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarIncidencias
    @estado              varchar(20) = NULL,
    @id_tipo_incidencia  int         = NULL,
    @id_conexion         int         = NULL,
    @desde               date        = NULL,
    @hasta               date        = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT i.id_incidencia, ti.nombre_incidencia AS tipo, i.prioridad, i.estado,
           i.fecha_incidente, i.descripcion, i.ubicacion,
           m.numero_serie AS medidor, m.id_conexion,
           dbo.fn_CalcularTiempoResolucion(i.id_incidencia) AS horas_resolucion,
           dbo.fn_ObtenerSLAPrioridad(i.prioridad) AS sla_horas,
           dbo.fn_VerificarCumplimientoSLA(i.id_incidencia) AS estado_sla
    FROM dbo.Incidencia i
    JOIN dbo.Tipo_Incidencia ti ON ti.id_tipo_incidencia = i.id_tipo_incidencia
    JOIN dbo.Medidor m          ON m.id_medidor = i.id_medidor
    WHERE (@estado             IS NULL OR i.estado = @estado)
      AND (@id_tipo_incidencia IS NULL OR i.id_tipo_incidencia = @id_tipo_incidencia)
      AND (@id_conexion        IS NULL OR m.id_conexion = @id_conexion)
      AND (@desde              IS NULL OR i.fecha_incidente >= @desde)
      AND (@hasta              IS NULL OR i.fecha_incidente <  DATEADD(DAY, 1, @hasta))
    ORDER BY i.fecha_incidente DESC;
END;
GO

-- Escala o ajusta la prioridad de una incidencia no resuelta y deja traza en Historial_Incidencia.
CREATE OR ALTER PROCEDURE dbo.sp_EscalarPrioridadIncidencia
    @id_incidencia    int,
    @nueva_prioridad  varchar(10)   = NULL,
    @observacion      varchar(4000)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado varchar(20), @prioridad_actual varchar(10), @nota varchar(4000);

    SELECT @estado = estado, @prioridad_actual = prioridad
    FROM dbo.Incidencia
    WHERE id_incidencia = @id_incidencia;

    IF @estado IS NULL
        THROW 50405, 'La incidencia indicada no existe.', 1;

    IF @estado = 'Resuelta'
        THROW 50409, 'La incidencia ya está resuelta.', 1;

    IF NULLIF(LTRIM(@observacion), '') IS NULL
        THROW 50427, 'Debe indicar el motivo o la observación del cambio de prioridad.', 1;

    IF @nueva_prioridad IS NULL
        SET @nueva_prioridad = CASE @prioridad_actual
            WHEN 'Baja'  THEN 'Media'
            WHEN 'Media' THEN 'Alta'
            ELSE 'Alta'
        END;

    IF @nueva_prioridad NOT IN ('Alta', 'Media', 'Baja')
        THROW 50426, 'Prioridad no válida. Use: Alta, Media o Baja.', 1;

    IF @nueva_prioridad = @prioridad_actual
        THROW 50428, 'La incidencia ya tiene asignada esa prioridad.', 1;

    SET @nota = CONCAT('Prioridad cambiada [', ISNULL(@prioridad_actual, 'N/A'), ' -> ', @nueva_prioridad, ']: ', @observacion);

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Incidencia
        SET prioridad = @nueva_prioridad,
            fecha_modificacion = GETDATE()
        WHERE id_incidencia = @id_incidencia;

        INSERT INTO dbo.Historial_Incidencia (id_incidencia, id_empleado, estado_anterior, estado_actual, fecha_evento, observacion)
        VALUES (@id_incidencia, dbo.fn_EmpleadoActual(), @estado, @estado, GETDATE(), @nota);

        INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
        VALUES (dbo.fn_UsuarioActual(), 'UPDATE', 'Incidencia',
                CONCAT('Incidencia ', @id_incidencia, ': ', @nota));

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

-- Reabre una incidencia marcada como 'Resuelta' cuando el problema persiste en campo.
CREATE OR ALTER PROCEDURE dbo.sp_ReabrirIncidencia
    @id_incidencia int,
    @motivo        varchar(4000)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado varchar(20), @prioridad varchar(10), @id_conexion int;

    SELECT @estado = i.estado, @prioridad = i.prioridad, @id_conexion = m.id_conexion
    FROM dbo.Incidencia i
    JOIN dbo.Medidor m ON m.id_medidor = i.id_medidor
    WHERE i.id_incidencia = @id_incidencia;

    IF @estado IS NULL
        THROW 50405, 'La incidencia indicada no existe.', 1;

    IF @estado <> 'Resuelta'
        THROW 50429, 'Solo se pueden reabrir incidencias que estén en estado Resuelta.', 1;

    IF NULLIF(LTRIM(@motivo), '') IS NULL
        THROW 50430, 'Debe indicar el motivo para reabrir la incidencia.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @obs varchar(4000) = CONCAT('Incidencia reabierta: ', @motivo);
        EXEC dbo.sp_CambiarEstadoIncidencia
            @id_incidencia = @id_incidencia,
            @nuevo_estado  = 'Abierta',
            @observacion   = @obs;

        -- Si la conexión presenta reincidencia reciente y no tenía prioridad Alta, se eleva a Alta.
        IF @prioridad <> 'Alta' AND dbo.fn_ContarIncidenciasReincidentes(@id_conexion, 90) >= 2
        BEGIN
            UPDATE dbo.Incidencia
            SET prioridad = 'Alta', fecha_modificacion = GETDATE()
            WHERE id_incidencia = @id_incidencia;
        END

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

-- Asigna una incidencia automáticamente al fontanero activo con menor carga de trabajo
-- (fn_ContarCargaActivaEmpleado) y mayor índice de eficiencia (fn_ObtenerIndiceEficienciaEmpleado).
CREATE OR ALTER PROCEDURE dbo.sp_AsignarMantenimientoAutomatico
    @id_incidencia         int,
    @id_tipo_trabajo       int,
    @descripcion           varchar(100) = NULL,
    @fecha_inicio          datetime     = NULL,
    @id_empleado_asignado  int          = NULL OUTPUT,
    @id_mantenimiento      int          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT TOP (1) @id_empleado_asignado = e.id_empleado
    FROM dbo.Empleado e
    LEFT JOIN dbo.Usuario_Sistema u ON u.id_empleado = e.id_empleado
    LEFT JOIN dbo.Rol r             ON r.id_rol = u.id_rol
    WHERE e.activo = 1
      AND (e.puesto LIKE '%Fontaner%' OR r.nombre_rol = 'Fontanero')
    ORDER BY dbo.fn_ContarCargaActivaEmpleado(e.id_empleado) ASC,
             dbo.fn_ObtenerIndiceEficienciaEmpleado(e.id_empleado) DESC,
             e.id_empleado ASC;

    -- Si no hay un empleado con puesto/rol de Fontanero, se toma el empleado activo con menor carga.
    IF @id_empleado_asignado IS NULL
        SELECT TOP (1) @id_empleado_asignado = e.id_empleado
        FROM dbo.Empleado e
        WHERE e.activo = 1
        ORDER BY dbo.fn_ContarCargaActivaEmpleado(e.id_empleado) ASC,
                 e.id_empleado ASC;

    IF @id_empleado_asignado IS NULL
        THROW 50431, 'No hay empleados activos disponibles para asignar el mantenimiento.', 1;

    EXEC dbo.sp_AsignarMantenimiento
        @id_incidencia    = @id_incidencia,
        @id_empleado      = @id_empleado_asignado,
        @id_tipo_trabajo  = @id_tipo_trabajo,
        @descripcion      = @descripcion,
        @fecha_inicio     = @fecha_inicio,
        @id_mantenimiento = @id_mantenimiento OUTPUT;
END;
GO

   --Historial de incidencia
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarHistorialIncidencia
    @id_incidencia int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT h.id_historial_incidencia, h.fecha_evento, h.estado_anterior, h.estado_actual,
           CONCAT_WS(' ', e.nombre_empleado, e.apellido1_empleado) AS empleado, h.observacion
    FROM dbo.Historial_Incidencia h
    LEFT JOIN dbo.Empleado e ON e.id_empleado = h.id_empleado
    WHERE h.id_incidencia = @id_incidencia
    ORDER BY h.fecha_evento, h.id_historial_incidencia;
END;
GO

   --Mantenimiento
-- Crea un mantenimiento a partir de una incidencia o de forma directa (preventivo).
CREATE OR ALTER PROCEDURE dbo.sp_ProgramarMantenimiento
    @id_empleado       int,
    @id_tipo_trabajo   int,
    @id_conexion       int,
    @descripcion       varchar(100) = NULL,
    @id_incidencia     int          = NULL,
    @fecha_inicio      datetime     = NULL,
    @id_mantenimiento  int          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Empleado WHERE id_empleado = @id_empleado AND activo = 1)
        THROW 50410, 'El empleado no existe o está inactivo.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Tipo_Trabajo WHERE id_tipo_trabajo = @id_tipo_trabajo AND activo = 1)
        THROW 50411, 'El tipo de trabajo no existe o está inactivo.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Conexion WHERE id_conexion = @id_conexion)
        THROW 50412, 'La conexión indicada no existe.', 1;

    IF @id_incidencia IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Incidencia WHERE id_incidencia = @id_incidencia)
        THROW 50405, 'La incidencia indicada no existe.', 1;

    IF @descripcion IS NULL
        SELECT @descripcion = LEFT(CONCAT('Atención de incidencia: ', descripcion), 100)
        FROM dbo.Incidencia WHERE id_incidencia = @id_incidencia;

    IF @descripcion IS NULL
        THROW 50413, 'Debe describir el trabajo de mantenimiento.', 1;

    INSERT INTO dbo.Mantenimiento (id_empleado, id_tipo_trabajo, id_conexion, id_incidencia, descripcion, fecha_inicio)
    VALUES (@id_empleado, @id_tipo_trabajo, @id_conexion, @id_incidencia, @descripcion, ISNULL(@fecha_inicio, GETDATE()));

    SET @id_mantenimiento = SCOPE_IDENTITY();
END;
GO

-- Cambia el estado de un mantenimiento (Programado -> En proceso, o Cancelado).
CREATE OR ALTER PROCEDURE dbo.sp_CambiarEstadoMantenimiento
    @id_mantenimiento int,
    @nuevo_estado     varchar(20),
    @anotacion        varchar(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado varchar(20);
    SELECT @estado = estado FROM dbo.Mantenimiento WHERE id_mantenimiento = @id_mantenimiento;

    IF @estado IS NULL
        THROW 50414, 'El mantenimiento indicado no existe.', 1;

    IF @estado IN ('Finalizado', 'Cancelado')
        THROW 50415, 'El mantenimiento ya está cerrado.', 1;

    IF @nuevo_estado NOT IN ('Programado', 'En proceso', 'Cancelado')
        THROW 50416, 'Estado no válido. Para finalizar use sp_CerrarMantenimiento.', 1;

    EXEC sys.sp_set_session_context @key = N'comentario', @value = @anotacion;

    UPDATE dbo.Mantenimiento
    SET estado = @nuevo_estado,
        fecha_fin = CASE WHEN @nuevo_estado = 'Cancelado' THEN GETDATE() END,
        fecha_modificacion = GETDATE()
    WHERE id_mantenimiento = @id_mantenimiento;

    EXEC sys.sp_set_session_context @key = N'comentario', @value = NULL;
END;
GO

-- Finaliza un mantenimiento. Si viene de una incidencia y ya no le quedan
-- mantenimientos abiertos, la incidencia se marca como resuelta.
-- Un fontanero solo puede cerrar los mantenimientos que tiene asignados.
CREATE OR ALTER PROCEDURE dbo.sp_CerrarMantenimiento
    @id_mantenimiento   int,
    @detalle            varchar(4000),
    @fecha_fin          datetime = NULL,
    @cerrar_incidencia  bit      = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado varchar(20), @id_incidencia int, @id_empleado int, @fecha_inicio datetime;

    SELECT @estado = estado, @id_incidencia = id_incidencia, @id_empleado = id_empleado, @fecha_inicio = fecha_inicio
    FROM dbo.Mantenimiento WHERE id_mantenimiento = @id_mantenimiento;

    IF @estado IS NULL
        THROW 50414, 'El mantenimiento indicado no existe.', 1;

    IF @estado IN ('Finalizado', 'Cancelado')
        THROW 50415, 'El mantenimiento ya está cerrado.', 1;

    IF NULLIF(LTRIM(@detalle), '') IS NULL
        THROW 50417, 'Debe describir el trabajo realizado.', 1;

    SET @fecha_fin = ISNULL(@fecha_fin, GETDATE());
    IF @fecha_fin < @fecha_inicio
        THROW 50418, 'La fecha de cierre no puede ser anterior a la de inicio.', 1;

    IF EXISTS (SELECT 1
               FROM dbo.Usuario_Sistema u JOIN dbo.Rol r ON r.id_rol = u.id_rol
               WHERE u.id_usuario_sistema = dbo.fn_UsuarioActual()
                 AND r.nombre_rol = 'Fontanero'
                 AND u.id_empleado <> @id_empleado)
        THROW 50419, 'Un fontanero solo puede cerrar los mantenimientos que tiene asignados.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC sys.sp_set_session_context @key = N'comentario', @value = @detalle;

        UPDATE dbo.Mantenimiento
        SET estado = 'Finalizado', fecha_fin = @fecha_fin, fecha_modificacion = GETDATE()
        WHERE id_mantenimiento = @id_mantenimiento;

        EXEC sys.sp_set_session_context @key = N'comentario', @value = NULL;

        IF @cerrar_incidencia = 1
           AND @id_incidencia IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.Mantenimiento
                           WHERE id_incidencia = @id_incidencia AND estado IN ('Programado', 'En proceso'))
           AND EXISTS (SELECT 1 FROM dbo.Incidencia WHERE id_incidencia = @id_incidencia AND estado <> 'Resuelta')
        BEGIN
            EXEC dbo.sp_CerrarIncidente @id_incidencia = @id_incidencia, @solucion = @detalle;
        END

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC sys.sp_set_session_context @key = N'comentario', @value = NULL;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarMantenimientos
    @estado        varchar(20) = NULL,
    @id_empleado   int         = NULL,
    @id_conexion   int         = NULL,
    @id_incidencia int         = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT mt.id_mantenimiento, mt.estado, tt.nombre_trabajo AS tipo_trabajo,
           mt.id_empleado, CONCAT_WS(' ', e.nombre_empleado, e.apellido1_empleado) AS responsable,
           mt.id_conexion, c.ubicacion, mt.id_incidencia, mt.descripcion,
           mt.fecha_inicio, mt.fecha_fin,
           dbo.fn_CalcularDuracionMantenimiento(mt.id_mantenimiento) AS horas_duracion
    FROM dbo.Mantenimiento mt
    JOIN dbo.Tipo_Trabajo tt ON tt.id_tipo_trabajo = mt.id_tipo_trabajo
    JOIN dbo.Empleado     e  ON e.id_empleado = mt.id_empleado
    JOIN dbo.Conexion     c  ON c.id_conexion = mt.id_conexion
    WHERE (@estado        IS NULL OR mt.estado = @estado)
      AND (@id_empleado   IS NULL OR mt.id_empleado = @id_empleado)
      AND (@id_conexion   IS NULL OR mt.id_conexion = @id_conexion)
      AND (@id_incidencia IS NULL OR mt.id_incidencia = @id_incidencia)
    ORDER BY mt.fecha_inicio DESC;
END;
GO

-- Reasigna un mantenimiento activo ('Programado' o 'En proceso') a otro empleado activo
-- y deja constancia en Historial_Mantenimiento y Bitacora.
CREATE OR ALTER PROCEDURE dbo.sp_ReasignarMantenimiento
    @id_mantenimiento   int,
    @id_nuevo_empleado  int,
    @motivo             varchar(4000)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado varchar(20), @id_empleado_anterior int, @nombre_anterior varchar(60), @nombre_nuevo varchar(60), @anotacion varchar(4000);

    SELECT @estado = estado, @id_empleado_anterior = id_empleado
    FROM dbo.Mantenimiento
    WHERE id_mantenimiento = @id_mantenimiento;

    IF @estado IS NULL
        THROW 50414, 'El mantenimiento indicado no existe.', 1;

    IF @estado IN ('Finalizado', 'Cancelado')
        THROW 50415, 'El mantenimiento ya está cerrado y no puede reasignarse.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Empleado WHERE id_empleado = @id_nuevo_empleado AND activo = 1)
        THROW 50410, 'El nuevo empleado no existe o está inactivo.', 1;

    IF @id_empleado_anterior = @id_nuevo_empleado
        THROW 50424, 'El mantenimiento ya está asignado a ese empleado.', 1;

    IF NULLIF(LTRIM(@motivo), '') IS NULL
        THROW 50425, 'Debe indicar el motivo de la reasignación.', 1;

    SELECT @nombre_anterior = CONCAT_WS(' ', nombre_empleado, apellido1_empleado) FROM dbo.Empleado WHERE id_empleado = @id_empleado_anterior;
    SELECT @nombre_nuevo    = CONCAT_WS(' ', nombre_empleado, apellido1_empleado) FROM dbo.Empleado WHERE id_empleado = @id_nuevo_empleado;
    SET @anotacion = CONCAT('Reasignado de ', @nombre_anterior, ' a ', @nombre_nuevo, '. Motivo: ', @motivo);

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Mantenimiento
        SET id_empleado = @id_nuevo_empleado,
            fecha_modificacion = GETDATE()
        WHERE id_mantenimiento = @id_mantenimiento;

        INSERT INTO dbo.Historial_Mantenimiento (id_mantenimiento, id_empleado, estado_anterior, estado_actual, fecha_evento, anotacion)
        VALUES (@id_mantenimiento, ISNULL(dbo.fn_EmpleadoActual(), @id_nuevo_empleado), @estado, @estado, GETDATE(), @anotacion);

        INSERT INTO dbo.Bitacora (id_usuario_sistema, accion, tabla_afectada, descripcion)
        VALUES (dbo.fn_UsuarioActual(), 'UPDATE', 'Mantenimiento',
                CONCAT('Mantenimiento ', @id_mantenimiento, ': ', @anotacion));

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

-- Programa mantenimientos preventivos masivos para conexiones activas sin órdenes pendientes
-- que superen @dias_sin_mantenimiento desde su último mantenimiento o tengan reincidencia.
CREATE OR ALTER PROCEDURE dbo.sp_ProgramarMantenimientoPreventivoMasivo
    @id_tipo_trabajo         int,
    @id_empleado             int          = NULL,
    @dias_sin_mantenimiento  int          = 180,
    @descripcion             varchar(100) = NULL,
    @fecha_inicio            datetime     = NULL,
    @cantidad_programados    int          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Tipo_Trabajo WHERE id_tipo_trabajo = @id_tipo_trabajo AND activo = 1)
        THROW 50411, 'El tipo de trabajo no existe o está inactivo.', 1;

    IF @id_empleado IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Empleado WHERE id_empleado = @id_empleado AND activo = 1)
        THROW 50410, 'El empleado indicado no existe o está inactivo.', 1;

    IF @dias_sin_mantenimiento <= 0
        THROW 50432, 'Los días sin mantenimiento deben ser mayores que cero.', 1;

    SET @descripcion = ISNULL(NULLIF(LTRIM(@descripcion), ''), CONCAT('Mantenimiento preventivo programado (> ', @dias_sin_mantenimiento, ' días)'));
    SET @fecha_inicio = ISNULL(@fecha_inicio, GETDATE());

    DECLARE @candidatas TABLE (id_conexion int PRIMARY KEY);
    DECLARE @creados TABLE (id_mantenimiento int, id_conexion int, id_empleado int, descripcion varchar(100));

    INSERT INTO @candidatas (id_conexion)
    SELECT c.id_conexion
    FROM dbo.Conexion c
    CROSS APPLY dbo.fn_ResumenOperativoConexion(c.id_conexion) r
    WHERE c.estado = 'Activa'
      AND r.mantenimientos_pendientes = 0
      AND (
          r.ultimo_mantenimiento IS NULL
          OR DATEDIFF(DAY, r.ultimo_mantenimiento, GETDATE()) >= @dias_sin_mantenimiento
          OR r.incidencias_90_dias >= 2
      );

    DECLARE @c int, @emp int, @id_mant int;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT id_conexion FROM @candidatas ORDER BY id_conexion;

    BEGIN TRY
        BEGIN TRANSACTION;

        OPEN cur;
        FETCH NEXT FROM cur INTO @c;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @emp = @id_empleado;
            IF @emp IS NULL
                SELECT TOP (1) @emp = e.id_empleado
                FROM dbo.Empleado e
                WHERE e.activo = 1
                ORDER BY dbo.fn_ContarCargaActivaEmpleado(e.id_empleado) ASC,
                         dbo.fn_ObtenerIndiceEficienciaEmpleado(e.id_empleado) DESC,
                         e.id_empleado ASC;

            IF @emp IS NULL
                THROW 50431, 'No hay empleados activos disponibles para programar el plan preventivo.', 1;

            EXEC dbo.sp_ProgramarMantenimiento
                @id_empleado      = @emp,
                @id_tipo_trabajo  = @id_tipo_trabajo,
                @id_conexion      = @c,
                @descripcion      = @descripcion,
                @fecha_inicio     = @fecha_inicio,
                @id_mantenimiento = @id_mant OUTPUT;

            INSERT INTO @creados VALUES (@id_mant, @c, @emp, @descripcion);
            FETCH NEXT FROM cur INTO @c;
        END
        CLOSE cur;
        DEALLOCATE cur;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH

    SELECT @cantidad_programados = COUNT(*) FROM @creados;

    SELECT cr.id_mantenimiento, cr.id_conexion, c.ubicacion,
           CONCAT_WS(' ', e.nombre_empleado, e.apellido1_empleado) AS responsable,
           cr.descripcion, @fecha_inicio AS fecha_inicio
    FROM @creados cr
    JOIN dbo.Conexion c ON c.id_conexion = cr.id_conexion
    JOIN dbo.Empleado e ON e.id_empleado = cr.id_empleado
    ORDER BY cr.id_mantenimiento;
END;
GO

-- Diagnóstico operativo integral de incidencias, SLA, carga de trabajo por empleado
-- y conexiones con reincidencia o mantenimientos pendientes.
CREATE OR ALTER PROCEDURE dbo.sp_ResumenOperativoMantenimientos
    @desde date = NULL,
    @hasta date = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Cumplimiento de SLA por prioridad de incidencia
    SELECT
        i.prioridad,
        dbo.fn_ObtenerSLAPrioridad(i.prioridad) AS sla_objetivo_horas,
        COUNT(*) AS total_incidencias,
        SUM(CASE WHEN i.estado <> 'Resuelta' THEN 1 ELSE 0 END) AS abiertas_o_en_proceso,
        SUM(CASE WHEN i.estado = 'Resuelta' THEN 1 ELSE 0 END) AS resueltas,
        SUM(CASE WHEN dbo.fn_VerificarCumplimientoSLA(i.id_incidencia) = 'En tiempo' THEN 1 ELSE 0 END) AS en_tiempo,
        SUM(CASE WHEN dbo.fn_VerificarCumplimientoSLA(i.id_incidencia) = 'Por vencer' THEN 1 ELSE 0 END) AS por_vencer,
        SUM(CASE WHEN dbo.fn_VerificarCumplimientoSLA(i.id_incidencia) = 'Vencida' THEN 1 ELSE 0 END) AS vencidas_sla,
        CAST(AVG(CAST(dbo.fn_CalcularTiempoResolucion(i.id_incidencia) AS decimal(10,2))) AS decimal(10,2)) AS horas_promedio_resolucion
    FROM dbo.Incidencia i
    WHERE (@desde IS NULL OR i.fecha_incidente >= @desde)
      AND (@hasta IS NULL OR i.fecha_incidente < DATEADD(DAY, 1, @hasta))
    GROUP BY i.prioridad
    ORDER BY CASE i.prioridad WHEN 'Alta' THEN 1 WHEN 'Media' THEN 2 ELSE 3 END;

    -- 2. Carga activa y eficiencia operativa por empleado
    SELECT
        e.id_empleado,
        CONCAT_WS(' ', e.nombre_empleado, e.apellido1_empleado, e.apellido2_empleado) AS empleado,
        e.puesto,
        dbo.fn_ContarCargaActivaEmpleado(e.id_empleado) AS carga_activa,
        SUM(CASE WHEN mt.estado = 'Finalizado' THEN 1 ELSE 0 END) AS mantenimientos_finalizados,
        CAST(AVG(CAST(dbo.fn_CalcularDuracionMantenimiento(mt.id_mantenimiento) AS decimal(10,2))) AS decimal(10,2)) AS horas_promedio_trabajo,
        dbo.fn_ObtenerIndiceEficienciaEmpleado(e.id_empleado) AS porcentaje_eficiencia
    FROM dbo.Empleado e
    LEFT JOIN dbo.Mantenimiento mt ON mt.id_empleado = e.id_empleado
        AND (@desde IS NULL OR mt.fecha_inicio >= @desde)
        AND (@hasta IS NULL OR mt.fecha_inicio < DATEADD(DAY, 1, @hasta))
    WHERE e.activo = 1
    GROUP BY e.id_empleado, e.nombre_empleado, e.apellido1_empleado, e.apellido2_empleado, e.puesto
    ORDER BY carga_activa DESC, porcentaje_eficiencia DESC;

    -- 3. Estado operativo por conexión (usando fn_ResumenOperativoConexion)
    SELECT
        r.id_conexion,
        r.abonado,
        r.ubicacion,
        r.estado_conexion,
        r.total_incidencias,
        r.incidencias_abiertas,
        r.incidencias_90_dias,
        r.total_mantenimientos,
        r.mantenimientos_pendientes,
        r.ultimo_mantenimiento,
        CAST(r.horas_promedio_resolucion AS decimal(10,2)) AS horas_promedio_resolucion
    FROM dbo.Conexion c
    CROSS APPLY dbo.fn_ResumenOperativoConexion(c.id_conexion) r
    WHERE r.total_incidencias > 0 OR r.total_mantenimientos > 0
    ORDER BY r.incidencias_abiertas DESC, r.incidencias_90_dias DESC, r.mantenimientos_pendientes DESC;
END;
GO

   --Historial de mantenimiento
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarHistorialMantenimiento
    @id_mantenimiento int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT h.id_historial_mantenimiento, h.fecha_evento, h.estado_anterior, h.estado_actual,
           CONCAT_WS(' ', e.nombre_empleado, e.apellido1_empleado) AS empleado, h.anotacion
    FROM dbo.Historial_Mantenimiento h
    LEFT JOIN dbo.Empleado e ON e.id_empleado = h.id_empleado
    WHERE h.id_mantenimiento = @id_mantenimiento
    ORDER BY h.fecha_evento, h.id_historial_mantenimiento;
END;
GO

   --Empleado
CREATE OR ALTER PROCEDURE dbo.sp_AgregarEmpleado
    @cedula              varchar(20),
    @nombre_empleado     varchar(20),
    @apellido1_empleado  varchar(20),
    @apellido2_empleado  varchar(20) = NULL,
    @puesto              varchar(20),
    @telefono            varchar(15) = NULL,
    @fecha_contratacion  datetime    = NULL,
    @id_empleado         int         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @cedula = REPLACE(REPLACE(LTRIM(RTRIM(@cedula)), '-', ''), ' ', '');

    IF dbo.fn_ValidarIdentificacion('FISICA', @cedula) = 0
       AND dbo.fn_ValidarIdentificacion('DIMEX', @cedula) = 0
        THROW 50420, 'La cédula del empleado no tiene un formato válido (física de 9 dígitos o DIMEX).', 1;

    IF EXISTS (SELECT 1 FROM dbo.Empleado WHERE cedula = @cedula)
        THROW 50421, 'Ya existe un empleado con esa cédula.', 1;

    INSERT INTO dbo.Empleado (cedula, nombre_empleado, apellido1_empleado, apellido2_empleado, puesto, telefono, fecha_contratacion)
    VALUES (@cedula, @nombre_empleado, @apellido1_empleado, @apellido2_empleado, @puesto, @telefono, ISNULL(@fecha_contratacion, GETDATE()));

    SET @id_empleado = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarEmpleados
    @cedula  varchar(20) = NULL,
    @nombre  varchar(60) = NULL,
    @puesto  varchar(20) = NULL,
    @activo  bit         = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.id_empleado, e.cedula,
           CONCAT_WS(' ', e.nombre_empleado, e.apellido1_empleado, e.apellido2_empleado) AS nombre_completo,
           e.puesto, e.telefono, e.fecha_contratacion, e.activo,
           u.nombre_usuario, r.nombre_rol
    FROM dbo.Empleado e
    LEFT JOIN dbo.Usuario_Sistema u ON u.id_empleado = e.id_empleado
    LEFT JOIN dbo.Rol r             ON r.id_rol = u.id_rol
    WHERE (@cedula IS NULL OR e.cedula = @cedula)
      AND (@nombre IS NULL OR CONCAT_WS(' ', e.nombre_empleado, e.apellido1_empleado, e.apellido2_empleado) LIKE '%' + @nombre + '%')
      AND (@puesto IS NULL OR e.puesto = @puesto)
      AND (@activo IS NULL OR e.activo = @activo)
    ORDER BY e.apellido1_empleado, e.nombre_empleado;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ModificarEmpleado
    @id_empleado         int,
    @cedula              varchar(20) = NULL,
    @nombre_empleado     varchar(20) = NULL,
    @apellido1_empleado  varchar(20) = NULL,
    @apellido2_empleado  varchar(20) = NULL,
    @puesto              varchar(20) = NULL,
    @telefono            varchar(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Empleado WHERE id_empleado = @id_empleado)
        THROW 50422, 'El empleado indicado no existe.', 1;

    IF @cedula IS NOT NULL
    BEGIN
        SET @cedula = REPLACE(REPLACE(LTRIM(RTRIM(@cedula)), '-', ''), ' ', '');

        IF dbo.fn_ValidarIdentificacion('FISICA', @cedula) = 0
           AND dbo.fn_ValidarIdentificacion('DIMEX', @cedula) = 0
            THROW 50420, 'La cédula del empleado no tiene un formato válido (física de 9 dígitos o DIMEX).', 1;

        IF EXISTS (SELECT 1 FROM dbo.Empleado WHERE cedula = @cedula AND id_empleado <> @id_empleado)
            THROW 50421, 'Ya existe un empleado con esa cédula.', 1;
    END

    UPDATE dbo.Empleado
    SET cedula             = ISNULL(@cedula, cedula),
        nombre_empleado    = ISNULL(@nombre_empleado, nombre_empleado),
        apellido1_empleado = ISNULL(@apellido1_empleado, apellido1_empleado),
        apellido2_empleado = ISNULL(@apellido2_empleado, apellido2_empleado),
        puesto             = ISNULL(@puesto, puesto),
        telefono           = ISNULL(@telefono, telefono)
    WHERE id_empleado = @id_empleado;
END;
GO

-- Activa o desactiva un empleado sin borrar su historial.
-- Al desactivarlo también se revoca el acceso de su usuario del sistema.
CREATE OR ALTER PROCEDURE dbo.sp_CambiarEstadoEmpleado
    @id_empleado int,
    @activo      bit
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Empleado WHERE id_empleado = @id_empleado)
        THROW 50422, 'El empleado indicado no existe.', 1;

    IF @activo = 0 AND EXISTS (SELECT 1 FROM dbo.Mantenimiento
                               WHERE id_empleado = @id_empleado AND estado IN ('Programado', 'En proceso'))
        THROW 50423, 'El empleado tiene mantenimientos abiertos. Reasígnelos antes de desactivarlo.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Empleado SET activo = @activo WHERE id_empleado = @id_empleado;

        IF @activo = 0
            UPDATE dbo.Usuario_Sistema SET activo = 0 WHERE id_empleado = @id_empleado AND activo = 1;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

-- Registra un trabajo que el fontanero ya realizó en una conexión (queda finalizado).
CREATE OR ALTER PROCEDURE dbo.sp_EmpleadoMantenimiento
    @id_empleado       int,
    @id_conexion       int,
    @id_tipo_trabajo   int,
    @descripcion       varchar(100),
    @fecha_inicio      datetime,
    @fecha_fin         datetime = NULL,
    @id_incidencia     int      = NULL,
    @id_mantenimiento  int      = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC dbo.sp_ProgramarMantenimiento
            @id_empleado      = @id_empleado,
            @id_tipo_trabajo  = @id_tipo_trabajo,
            @id_conexion      = @id_conexion,
            @descripcion      = @descripcion,
            @id_incidencia    = @id_incidencia,
            @fecha_inicio     = @fecha_inicio,
            @id_mantenimiento = @id_mantenimiento OUTPUT;

        EXEC dbo.sp_CerrarMantenimiento
            @id_mantenimiento = @id_mantenimiento,
            @detalle          = @descripcion,
            @fecha_fin        = @fecha_fin;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
