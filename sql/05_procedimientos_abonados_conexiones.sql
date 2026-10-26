SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Script 05: Procedimientos - Abonados, conexiones y medidores 
   --------------------------------------------------------------------*/
USE ASADA;
GO

   -- Abonado
-- Registra un abonado. Si el tipo de identificación es JURIDICA se guarda en
-- Abonado_Juridico; cualquier otro tipo (FISICA, DIMEX, NITE, PASAPORTE) va a Abonado_Fisico.
-- Para jurídicos, @nombre es la razón social.
CREATE OR ALTER PROCEDURE dbo.sp_Nuevo_Abonado
    @tipo_identificacion      varchar(20),
    @numero_identidad         varchar(50),
    @nombre                   varchar(50),
    @apellido1                varchar(50)  = NULL,
    @apellido2                varchar(50)  = NULL,
    @fecha_nacimiento         date         = NULL,
    @direccion                varchar(200),
    @telefono                 varchar(20)  = NULL,
    @correo_electronico       varchar(100) = NULL,
    @cedula_representante     varchar(20)  = NULL,
    @nombre_representante     varchar(50)  = NULL,
    @apellido1_representante  varchar(50)  = NULL,
    @apellido2_representante  varchar(50)  = NULL,
    @id_abonado               int          = NULL OUTPUT,
    @tipo_abonado             varchar(10)  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @tipo_identificacion = UPPER(LTRIM(RTRIM(@tipo_identificacion)));
    SET @numero_identidad    = REPLACE(REPLACE(LTRIM(RTRIM(@numero_identidad)), '-', ''), ' ', '');

    IF dbo.fn_ValidarIdentificacion(@tipo_identificacion, @numero_identidad) = 0
        THROW 50101, 'El número de identificación no tiene un formato válido para el tipo indicado.', 1;

    -- Una misma identificación no puede existir ni como físico ni como jurídico.
    IF EXISTS (SELECT 1 FROM dbo.Abonado_Fisico   WHERE numero_identidad = @numero_identidad)
       OR EXISTS (SELECT 1 FROM dbo.Abonado_Juridico WHERE cedula_juridica = @numero_identidad)
        THROW 50102, 'Ya existe un abonado registrado con esa identificación.', 1;

    IF @correo_electronico IS NOT NULL AND @correo_electronico NOT LIKE '%_@_%._%'
        THROW 50103, 'El correo electrónico no tiene un formato válido.', 1;

    IF @tipo_identificacion = 'JURIDICA'
    BEGIN
        IF @cedula_representante IS NULL OR @nombre_representante IS NULL OR @apellido1_representante IS NULL
            THROW 50104, 'Para un abonado jurídico se requieren los datos del representante legal.', 1;

        INSERT INTO dbo.Abonado_Juridico
            (cedula_juridica, razon_social, cedula_representante, nombre_representante,
             apellido1_representante, apellido2_representante, direccion, telefono, correo_electronico)
        VALUES
            (@numero_identidad, @nombre, @cedula_representante, @nombre_representante,
             @apellido1_representante, @apellido2_representante, @direccion, @telefono, @correo_electronico);

        SET @tipo_abonado = 'JURIDICO';
    END
    ELSE
    BEGIN
        IF @apellido1 IS NULL
            THROW 50105, 'Para un abonado físico se requiere al menos el primer apellido.', 1;

        IF @fecha_nacimiento IS NOT NULL AND DATEDIFF(YEAR, @fecha_nacimiento, GETDATE()) < 18
            THROW 50106, 'El abonado físico debe ser mayor de edad.', 1;

        INSERT INTO dbo.Abonado_Fisico
            (tipo_identificacion, numero_identidad, nombre, apellido1, apellido2,
             fecha_nacimiento, direccion, telefono, correo_electronico)
        VALUES
            (@tipo_identificacion, @numero_identidad, @nombre, @apellido1, @apellido2,
             @fecha_nacimiento, @direccion, @telefono, @correo_electronico);

        SET @tipo_abonado = 'FISICO';
    END

    SET @id_abonado = SCOPE_IDENTITY();
END;
GO

-- Consulta abonados por id, identificación o nombre (búsqueda parcial).
-- Devuelve dos resultados: los abonados encontrados y sus conexiones.
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarAbonado
    @id_abonado      int          = NULL,
    @tipo_abonado    varchar(10)  = NULL,   -- 'FISICO' o 'JURIDICO'
    @identificacion  varchar(50)  = NULL,
    @nombre          varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.*
    INTO #abonados
    FROM dbo.vw_Abonados a
    WHERE (@id_abonado     IS NULL OR a.id_abonado = @id_abonado)
      AND (@tipo_abonado   IS NULL OR a.tipo_abonado = @tipo_abonado)
      AND (@identificacion IS NULL OR a.identificacion = REPLACE(@identificacion, '-', ''))
      AND (@nombre         IS NULL OR a.nombre_completo LIKE '%' + @nombre + '%');

    SELECT * FROM #abonados ORDER BY nombre_completo;

    SELECT a.tipo_abonado, a.id_abonado, c.id_conexion, c.ubicacion, c.estado,
           tt.nombre_tarifa AS tipo_tarifa, c.fecha_conexion
    FROM #abonados a
    JOIN dbo.Conexion c
      ON (a.tipo_abonado = 'FISICO'   AND c.id_abonado_fisico   = a.id_abonado)
      OR (a.tipo_abonado = 'JURIDICO' AND c.id_abonado_juridico = a.id_abonado)
    JOIN dbo.Tarifa t       ON t.id_tarifa = c.id_tarifa
    JOIN dbo.Tipo_Tarifa tt ON tt.id_tipo_tarifa = t.id_tipo_tarifa
    ORDER BY a.id_abonado, c.id_conexion;
END;
GO

-- Actualiza datos de contacto y dirección 
CREATE OR ALTER PROCEDURE dbo.sp_ModificarAbonado
    @tipo_abonado             varchar(10),
    @id_abonado               int,
    @direccion                varchar(200) = NULL,
    @telefono                 varchar(20)  = NULL,
    @correo_electronico       varchar(100) = NULL,
    @nombre                   varchar(50)  = NULL,   -- nombre o razón social
    @apellido1                varchar(50)  = NULL,
    @apellido2                varchar(50)  = NULL,
    @cedula_representante     varchar(20)  = NULL,
    @nombre_representante     varchar(50)  = NULL,
    @apellido1_representante  varchar(50)  = NULL,
    @apellido2_representante  varchar(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @filas int = 0;

    IF @correo_electronico IS NOT NULL AND @correo_electronico NOT LIKE '%_@_%._%'
        THROW 50103, 'El correo electrónico no tiene un formato válido.', 1;

    IF @tipo_abonado = 'FISICO'
    BEGIN
        UPDATE dbo.Abonado_Fisico
        SET direccion          = ISNULL(@direccion, direccion),
            telefono           = ISNULL(@telefono, telefono),
            correo_electronico = ISNULL(@correo_electronico, correo_electronico),
            nombre             = ISNULL(@nombre, nombre),
            apellido1          = ISNULL(@apellido1, apellido1),
            apellido2          = ISNULL(@apellido2, apellido2)
        WHERE id_abonado_fisico = @id_abonado;
        SET @filas = @@ROWCOUNT;
    END
    ELSE IF @tipo_abonado = 'JURIDICO'
    BEGIN
        UPDATE dbo.Abonado_Juridico
        SET direccion               = ISNULL(@direccion, direccion),
            telefono                = ISNULL(@telefono, telefono),
            correo_electronico      = ISNULL(@correo_electronico, correo_electronico),
            razon_social            = ISNULL(@nombre, razon_social),
            cedula_representante    = ISNULL(@cedula_representante, cedula_representante),
            nombre_representante    = ISNULL(@nombre_representante, nombre_representante),
            apellido1_representante = ISNULL(@apellido1_representante, apellido1_representante),
            apellido2_representante = ISNULL(@apellido2_representante, apellido2_representante)
        WHERE id_abonado_juridico = @id_abonado;
        SET @filas = @@ROWCOUNT;
    END
    ELSE
        THROW 50107, 'El tipo de abonado debe ser FISICO o JURIDICO.', 1;

    IF @filas = 0
        THROW 50108, 'El abonado indicado no existe.', 1;
END;
GO

--no puede tener conexiones activas ni saldo pendiente
CREATE OR ALTER PROCEDURE dbo.sp_DesactivarAbonado
    @tipo_abonado varchar(10),
    @id_abonado   int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Conexion
               WHERE estado = 'Activa'
                 AND ((@tipo_abonado = 'FISICO'   AND id_abonado_fisico   = @id_abonado)
                   OR (@tipo_abonado = 'JURIDICO' AND id_abonado_juridico = @id_abonado)))
        THROW 50109, 'No se puede desactivar: el abonado tiene conexiones activas.', 1;

    IF EXISTS (SELECT 1
               FROM dbo.vw_SaldoFactura s
               JOIN dbo.Conexion c ON c.id_conexion = s.id_conexion
               WHERE s.saldo > 0
                 AND ((@tipo_abonado = 'FISICO'   AND c.id_abonado_fisico   = @id_abonado)
                   OR (@tipo_abonado = 'JURIDICO' AND c.id_abonado_juridico = @id_abonado)))
        THROW 50110, 'No se puede desactivar: el abonado tiene saldos pendientes.', 1;

    DECLARE @filas int = 0;

    IF @tipo_abonado = 'FISICO'
    BEGIN
        UPDATE dbo.Abonado_Fisico SET activo = 0 WHERE id_abonado_fisico = @id_abonado;
        SET @filas = @@ROWCOUNT;
    END
    ELSE IF @tipo_abonado = 'JURIDICO'
    BEGIN
        UPDATE dbo.Abonado_Juridico SET activo = 0 WHERE id_abonado_juridico = @id_abonado;
        SET @filas = @@ROWCOUNT;
    END
    ELSE
        THROW 50107, 'El tipo de abonado debe ser FISICO o JURIDICO.', 1;

    IF @filas = 0
        THROW 50108, 'El abonado indicado no existe.', 1;
END;
GO

-- Lista abonados con conexiones desactivadas (suspendidas, cortadas o inactivas).
CREATE OR ALTER PROCEDURE dbo.sp_AbonadoInactivo
    @estado varchar(25) = NULL   -- NULL = todos los estados distintos de 'Activa'
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.tipo_abonado, a.id_abonado, a.identificacion, a.nombre_completo, a.telefono,
           c.id_conexion, c.ubicacion, c.estado, c.fecha_modificacion
    FROM dbo.Conexion c
    JOIN dbo.vw_Abonados a
      ON (a.tipo_abonado = 'FISICO'   AND a.id_abonado = c.id_abonado_fisico)
      OR (a.tipo_abonado = 'JURIDICO' AND a.id_abonado = c.id_abonado_juridico)
    WHERE c.estado <> 'Activa'
      AND (@estado IS NULL OR c.estado = @estado)
    ORDER BY c.fecha_modificacion DESC;
END;
GO

-- Listado de abonados con facturas vencidas para el proceso de cobro.
CREATE OR ALTER PROCEDURE dbo.sp_GenerarReporteMorosidad
    @dias_minimos_atraso int = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT tipo_abonado, identificacion, nombre_completo, id_conexion,
           cantidad_facturas_vencidas, saldo_vencido, vencimiento_mas_antiguo, dias_atraso_maximo
    FROM dbo.vw_UsuariosMorosos
    WHERE dias_atraso_maximo >= @dias_minimos_atraso
    ORDER BY saldo_vencido DESC;
END;
GO

   --Conexión
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarConexion
    @tipo_abonado varchar(10),
    @id_abonado   int,
    @id_tarifa    int,
    @ubicacion    varchar(50),
    @id_conexion  int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @tipo_abonado = 'FISICO'
       AND NOT EXISTS (SELECT 1 FROM dbo.Abonado_Fisico WHERE id_abonado_fisico = @id_abonado AND activo = 1)
        THROW 50111, 'El abonado físico no existe o está inactivo.', 1;

    IF @tipo_abonado = 'JURIDICO'
       AND NOT EXISTS (SELECT 1 FROM dbo.Abonado_Juridico WHERE id_abonado_juridico = @id_abonado AND activo = 1)
        THROW 50112, 'El abonado jurídico no existe o está inactivo.', 1;

    IF @tipo_abonado NOT IN ('FISICO', 'JURIDICO')
        THROW 50107, 'El tipo de abonado debe ser FISICO o JURIDICO.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.vw_TarifasActivas WHERE id_tarifa = @id_tarifa)
        THROW 50113, 'La tarifa no existe o no está activa.', 1;

    -- No se permiten dos conexiones vigentes para la misma propiedad (ubicación).
    IF EXISTS (SELECT 1 FROM dbo.Conexion
               WHERE UPPER(LTRIM(RTRIM(ubicacion))) = UPPER(LTRIM(RTRIM(@ubicacion)))
                 AND estado <> 'Inactiva')
        THROW 50114, 'Ya existe una conexión registrada para esa ubicación.', 1;

    INSERT INTO dbo.Conexion (id_abonado_fisico, id_abonado_juridico, id_tarifa, ubicacion)
    VALUES (CASE WHEN @tipo_abonado = 'FISICO'   THEN @id_abonado END,
            CASE WHEN @tipo_abonado = 'JURIDICO' THEN @id_abonado END,
            @id_tarifa, LTRIM(RTRIM(@ubicacion)));

    SET @id_conexion = SCOPE_IDENTITY();
END;
GO

-- Cambia el estado de una conexión. El motivo queda en la bitácora
CREATE OR ALTER PROCEDURE dbo.sp_CambiarEstadoConexion
    @id_conexion  int,
    @nuevo_estado varchar(25),
    @motivo       varchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado_actual varchar(25);
    SELECT @estado_actual = estado FROM dbo.Conexion WHERE id_conexion = @id_conexion;

    IF @estado_actual IS NULL
        THROW 50115, 'La conexión indicada no existe.', 1;

    IF @nuevo_estado NOT IN ('Activa', 'Suspendida', 'Cortada', 'Inactiva')
        THROW 50116, 'Estado no válido. Use: Activa, Suspendida, Cortada o Inactiva.', 1;

    IF @estado_actual = @nuevo_estado
        THROW 50117, 'La conexión ya se encuentra en ese estado.', 1;

    IF NULLIF(LTRIM(@motivo), '') IS NULL
        THROW 50118, 'Debe indicar el motivo del cambio de estado.', 1;

    EXEC sys.sp_set_session_context @key = N'comentario', @value = @motivo;

    UPDATE dbo.Conexion
    SET estado = @nuevo_estado, fecha_modificacion = GETDATE()
    WHERE id_conexion = @id_conexion;

    EXEC sys.sp_set_session_context @key = N'comentario', @value = NULL;
END;
GO

--asigna o cambia la tarifa de una conexión.
CREATE OR ALTER PROCEDURE dbo.sp_AsignarTarifaConexion
    @id_conexion int,
    @id_tarifa   int,
    @motivo      varchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Conexion WHERE id_conexion = @id_conexion)
        THROW 50115, 'La conexión indicada no existe.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.vw_TarifasActivas WHERE id_tarifa = @id_tarifa)
        THROW 50113, 'La tarifa no existe o no está activa.', 1;

    EXEC sys.sp_set_session_context @key = N'comentario', @value = @motivo;

    UPDATE dbo.Conexion
    SET id_tarifa = @id_tarifa, fecha_modificacion = GETDATE()
    WHERE id_conexion = @id_conexion;

    EXEC sys.sp_set_session_context @key = N'comentario', @value = NULL;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarConexionesPorAbonado
    @tipo_abonado varchar(10),
    @id_abonado   int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT c.id_conexion, c.ubicacion, c.estado, c.fecha_conexion, c.fecha_modificacion,
           tt.nombre_tarifa AS tipo_tarifa, t.monto_fijo, t.monto_por_m3,
           m.id_medidor, m.numero_serie, m.ultima_lectura, m.fecha_ultima_lectura
    FROM dbo.Conexion c
    JOIN dbo.Tarifa t       ON t.id_tarifa = c.id_tarifa
    JOIN dbo.Tipo_Tarifa tt ON tt.id_tipo_tarifa = t.id_tipo_tarifa
    LEFT JOIN dbo.Medidor m ON m.id_conexion = c.id_conexion AND m.estado = 'Activo'
    WHERE (@tipo_abonado = 'FISICO'   AND c.id_abonado_fisico   = @id_abonado)
       OR (@tipo_abonado = 'JURIDICO' AND c.id_abonado_juridico = @id_abonado)
    ORDER BY c.estado, c.id_conexion;
END;
GO

   --Medidor
CREATE OR ALTER PROCEDURE dbo.sp_MedidorExiste
    @id_conexion int,
    @existe      bit OUTPUT,
    @id_medidor  int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT @id_medidor = id_medidor
    FROM dbo.Medidor
    WHERE id_conexion = @id_conexion AND estado = 'Activo';

    SET @existe = CASE WHEN @id_medidor IS NULL THEN 0 ELSE 1 END;
END;
GO

-- Instala un medidor nuevo. Si @sustituir = 1 y la conexión ya tiene uno activo,
-- el anterior se marca como 'Sustituido'; si no, se rechaza.
CREATE OR ALTER PROCEDURE dbo.sp_AsignarMedidorConexion
    @id_conexion      int,
    @numero_serie     varchar(20),
    @lectura_inicial  decimal(10,2) = 0,
    @sustituir        bit = 0,
    @id_medidor       int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @existe bit, @id_medidor_actual int;

    IF NOT EXISTS (SELECT 1 FROM dbo.Conexion WHERE id_conexion = @id_conexion AND estado <> 'Inactiva')
        THROW 50115, 'La conexión indicada no existe o está inactiva.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Medidor WHERE numero_serie = @numero_serie)
        THROW 50119, 'Ya existe un medidor con ese número de serie.', 1;

    IF @lectura_inicial < 0
        THROW 50120, 'La lectura inicial no puede ser negativa.', 1;

    EXEC dbo.sp_MedidorExiste @id_conexion = @id_conexion, @existe = @existe OUTPUT, @id_medidor = @id_medidor_actual OUTPUT;

    IF @existe = 1 AND @sustituir = 0
        THROW 50121, 'La conexión ya tiene un medidor activo. Use @sustituir = 1 para reemplazarlo.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @existe = 1
            UPDATE dbo.Medidor SET estado = 'Sustituido' WHERE id_medidor = @id_medidor_actual;

        INSERT INTO dbo.Medidor (id_conexion, numero_serie, ultima_lectura, fecha_ultima_lectura)
        VALUES (@id_conexion, @numero_serie, @lectura_inicial, GETDATE());

        SET @id_medidor = SCOPE_IDENTITY();

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

-- Cambia el estado del medidor (por defecto 'Retirado'). No borra el registro ni sus lecturas.
CREATE OR ALTER PROCEDURE dbo.sp_DesactivarMedidor
    @id_medidor   int,
    @nuevo_estado varchar(10) = 'Retirado',
    @motivo       varchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @nuevo_estado NOT IN ('Retirado', 'Dañado', 'Sustituido')
        THROW 50122, 'Estado no válido. Use: Retirado, Dañado o Sustituido.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Medidor WHERE id_medidor = @id_medidor)
        THROW 50123, 'El medidor indicado no existe.', 1;

    EXEC sys.sp_set_session_context @key = N'comentario', @value = @motivo;

    UPDATE dbo.Medidor SET estado = @nuevo_estado WHERE id_medidor = @id_medidor;

    EXEC sys.sp_set_session_context @key = N'comentario', @value = NULL;
END;
GO

--búsqueda de medidores por número de serie o conexión.
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarMedidores
    @numero_serie varchar(20) = NULL,
    @id_conexion  int         = NULL,
    @estado       varchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT m.id_medidor, m.numero_serie, m.estado, m.fecha_instalacion,
           m.ultima_lectura, m.fecha_ultima_lectura, m.id_conexion, c.ubicacion,
           dbo.fn_ObtenerNombreCompleto(c.id_abonado_fisico, c.id_abonado_juridico) AS abonado
    FROM dbo.Medidor m
    JOIN dbo.Conexion c ON c.id_conexion = m.id_conexion
    WHERE (@numero_serie IS NULL OR m.numero_serie LIKE '%' + @numero_serie + '%')
      AND (@id_conexion  IS NULL OR m.id_conexion = @id_conexion)
      AND (@estado       IS NULL OR m.estado = @estado)
    ORDER BY m.id_conexion, m.fecha_instalacion DESC;
END;
GO
