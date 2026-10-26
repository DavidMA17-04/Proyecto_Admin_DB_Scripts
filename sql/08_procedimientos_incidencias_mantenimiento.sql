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

        INSERT INTO dbo.Incidencia (id_medidor, id_tipo_incidencia, fecha_incidente, descripcion, ubicacion, prioridad)
        VALUES (@id_medidor, @id_tipo_incidencia, ISNULL(@fecha_incidente, GETDATE()), @descripcion, @ubicacion,
                dbo.fn_ClasificarIncidencia(@descripcion, @id_tipo_incidencia));

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
           dbo.fn_CalcularTiempoResolucion(i.id_incidencia) AS horas_resolucion
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
