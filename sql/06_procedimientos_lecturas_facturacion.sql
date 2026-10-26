SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Script 06: Procedimientos - Lecturas y facturación (R2)
   --------------------------------------------------------------------*/
USE ASADA;
GO

   --Lectura
-- Registra la lectura mensual. La lectura anterior se toma con fn_ObtenerUltimaLectura.
-- Al insertar se disparan trg_ActualizarUltimaLectura y trg_VerificarConsumoAlInsertar.
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarLectura
    @id_medidor      int,
    @lectura_actual  decimal(10,2),
    @fecha_lectura   datetime = NULL,
    @id_lectura      int = NULL OUTPUT,
    @consumo         decimal(10,2) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @lectura_anterior decimal(10,2), @ultima_fecha datetime;
    SET @fecha_lectura = ISNULL(@fecha_lectura, GETDATE());

    IF NOT EXISTS (SELECT 1 FROM dbo.Medidor WHERE id_medidor = @id_medidor AND estado = 'Activo')
        THROW 50201, 'El medidor no existe o no está activo.', 1;

    IF @fecha_lectura > GETDATE()
        THROW 50202, 'La fecha de la lectura no puede ser futura.', 1;

    SELECT TOP (1) @ultima_fecha = fecha_lectura_actual
    FROM dbo.Lectura WHERE id_medidor = @id_medidor
    ORDER BY fecha_lectura_actual DESC;

    IF @ultima_fecha IS NOT NULL AND @fecha_lectura <= @ultima_fecha
        THROW 50203, 'La fecha debe ser posterior a la última lectura registrada del medidor.', 1;

    IF @ultima_fecha IS NOT NULL
       AND dbo.fn_ObtenerPeriodoFiscal(@ultima_fecha) = dbo.fn_ObtenerPeriodoFiscal(@fecha_lectura)
        THROW 50204, 'El medidor ya tiene una lectura registrada en ese mes.', 1;

    SET @lectura_anterior = dbo.fn_ObtenerUltimaLectura(@id_medidor);
    SET @consumo = dbo.fn_CalcularConsumo(@lectura_anterior, @lectura_actual);

    IF @consumo IS NULL
        THROW 50205, 'La lectura actual no puede ser menor que la lectura anterior.', 1;

    INSERT INTO dbo.Lectura (id_medidor, fecha_lectura_actual, lectura_anterior, lectura_actual)
    VALUES (@id_medidor, @fecha_lectura, @lectura_anterior, @lectura_actual);

    SET @id_lectura = SCOPE_IDENTITY();
END;
GO

-- Corrige una lectura mal digitada. Solo se permite si aún no tiene factura y
-- si es la última lectura del medidor (para no romper la cadena de lecturas).
CREATE OR ALTER PROCEDURE dbo.sp_ActualizarLectura
    @id_lectura           int,
    @lectura_actual_nueva decimal(10,2),
    @motivo               varchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @id_medidor int, @lectura_anterior decimal(10,2);

    SELECT @id_medidor = id_medidor, @lectura_anterior = lectura_anterior
    FROM dbo.Lectura WHERE id_lectura = @id_lectura;

    IF @id_medidor IS NULL
        THROW 50206, 'La lectura indicada no existe.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Factura WHERE id_lectura = @id_lectura)
        THROW 50207, 'No se puede corregir: la lectura ya fue facturada.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Lectura WHERE id_medidor = @id_medidor AND id_lectura > @id_lectura)
        THROW 50208, 'Solo se puede corregir la última lectura del medidor.', 1;

    IF @lectura_actual_nueva < @lectura_anterior
        THROW 50205, 'La lectura actual no puede ser menor que la lectura anterior.', 1;

    IF NULLIF(LTRIM(@motivo), '') IS NULL
        THROW 50209, 'Debe indicar el motivo de la corrección.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC sys.sp_set_session_context @key = N'comentario', @value = @motivo;

        UPDATE dbo.Lectura SET lectura_actual = @lectura_actual_nueva WHERE id_lectura = @id_lectura;

        -- Las alertas de esa lectura se recalculan con el valor corregido.
        DELETE FROM dbo.Alerta_Consumo WHERE id_lectura = @id_lectura AND estado = 'Abierta' AND id_incidencia IS NULL;
        EXEC dbo.sp_DetectarConsumoAnomalo @id_lectura = @id_lectura;

        EXEC sys.sp_set_session_context @key = N'comentario', @value = NULL;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC sys.sp_set_session_context @key = N'comentario', @value = NULL;
        THROW;
    END CATCH
END;
GO

-- Historial de consumo por abonado, conexión o medidor en un rango de fechas.
CREATE OR ALTER PROCEDURE dbo.sp_HistorialConsumo
    @tipo_abonado varchar(10) = NULL,
    @id_abonado   int         = NULL,
    @id_conexion  int         = NULL,
    @id_medidor   int         = NULL,
    @desde        date        = NULL,
    @hasta        date        = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT c.id_conexion, c.ubicacion,
           dbo.fn_ObtenerNombreCompleto(c.id_abonado_fisico, c.id_abonado_juridico) AS abonado,
           m.id_medidor, m.numero_serie,
           l.id_lectura, l.fecha_lectura_actual, l.lectura_anterior, l.lectura_actual, l.consumo,
           f.id_factura, f.monto_total, f.estado AS estado_factura
    FROM dbo.Lectura l
    JOIN dbo.Medidor  m ON m.id_medidor = l.id_medidor
    JOIN dbo.Conexion c ON c.id_conexion = m.id_conexion
    LEFT JOIN dbo.Factura f ON f.id_lectura = l.id_lectura
    WHERE (@id_medidor  IS NULL OR m.id_medidor = @id_medidor)
      AND (@id_conexion IS NULL OR c.id_conexion = @id_conexion)
      AND (@id_abonado  IS NULL
           OR (@tipo_abonado = 'FISICO'   AND c.id_abonado_fisico   = @id_abonado)
           OR (@tipo_abonado = 'JURIDICO' AND c.id_abonado_juridico = @id_abonado))
      AND (@desde IS NULL OR l.fecha_lectura_actual >= @desde)
      AND (@hasta IS NULL OR l.fecha_lectura_actual <  DATEADD(DAY, 1, @hasta))
    ORDER BY c.id_conexion, l.fecha_lectura_actual DESC;
END;
GO

   --Factura
-- Genera la factura de una lectura con la tarifa vigente a la fecha de la lectura.
CREATE OR ALTER PROCEDURE dbo.sp_GenerarFactura
    @id_lectura  int,
    @dias_plazo  int = 15,
    @id_factura  int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @id_conexion int, @consumo decimal(10,2), @fecha_lectura datetime,
            @monto_fijo decimal(10,2), @monto_por_m3 decimal(10,2), @estado_conexion varchar(25);

    SELECT @id_conexion = m.id_conexion, @consumo = l.consumo, @fecha_lectura = l.fecha_lectura_actual,
           @estado_conexion = c.estado
    FROM dbo.Lectura l
    JOIN dbo.Medidor  m ON m.id_medidor = l.id_medidor
    JOIN dbo.Conexion c ON c.id_conexion = m.id_conexion
    WHERE l.id_lectura = @id_lectura;

    IF @id_conexion IS NULL
        THROW 50206, 'La lectura indicada no existe.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Factura WHERE id_lectura = @id_lectura)
        THROW 50210, 'La lectura ya tiene una factura generada.', 1;

    IF @estado_conexion = 'Inactiva'
        THROW 50211, 'No se factura una conexión inactiva.', 1;

    IF @dias_plazo NOT BETWEEN 1 AND 60
        THROW 50212, 'El plazo de pago debe estar entre 1 y 60 días.', 1;

    SELECT @monto_fijo = monto_fijo, @monto_por_m3 = monto_por_m3
    FROM dbo.fn_ObtenerTarifaVigente(@id_conexion, @fecha_lectura);

    INSERT INTO dbo.Factura (id_lectura, fecha_emision, fecha_vencimiento, monto_consumo, monto_fijo)
    VALUES (@id_lectura,
            GETDATE(),
            DATEADD(DAY, @dias_plazo, CAST(GETDATE() AS date)),
            dbo.fn_CalcularMontoFactura(@consumo, @monto_fijo, @monto_por_m3) - @monto_fijo,
            @monto_fijo);

    SET @id_factura = SCOPE_IDENTITY();
END;
GO

-- Genera las facturas de todas las lecturas del mes indicado que aún no tienen factura.
CREATE OR ALTER PROCEDURE dbo.sp_GenerarFacturacionMensual
    @anio        int,
    @mes         int,
    @dias_plazo  int = 15,
    @facturas_generadas int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @id_lectura int, @desde date = DATEFROMPARTS(@anio, @mes, 1);
    DECLARE @errores TABLE (id_lectura int, mensaje nvarchar(4000));
    SET @facturas_generadas = 0;

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT l.id_lectura
        FROM dbo.Lectura l
        JOIN dbo.Medidor  m ON m.id_medidor = l.id_medidor
        JOIN dbo.Conexion c ON c.id_conexion = m.id_conexion
        WHERE l.fecha_lectura_actual >= @desde
          AND l.fecha_lectura_actual <  DATEADD(MONTH, 1, @desde)
          AND c.estado <> 'Inactiva'
          AND NOT EXISTS (SELECT 1 FROM dbo.Factura f WHERE f.id_lectura = l.id_lectura);

    OPEN cur;
    FETCH NEXT FROM cur INTO @id_lectura;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC dbo.sp_GenerarFactura @id_lectura = @id_lectura, @dias_plazo = @dias_plazo;
            SET @facturas_generadas += 1;
        END TRY
        BEGIN CATCH
            INSERT INTO @errores VALUES (@id_lectura, ERROR_MESSAGE());
        END CATCH
        FETCH NEXT FROM cur INTO @id_lectura;
    END
    CLOSE cur;
    DEALLOCATE cur;

    SELECT @facturas_generadas AS facturas_generadas;
    IF EXISTS (SELECT 1 FROM @errores)
        SELECT * FROM @errores;
END;
GO

-- Marca como 'Vencida' toda factura pendiente cuya fecha límite ya pasó.
-- Lo ejecuta el job nocturno.
CREATE OR ALTER PROCEDURE dbo.sp_ActualizarFacturasVencidas
    @facturas_vencidas int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Factura
    SET estado = 'Vencida', fecha_modificacion = GETDATE()
    WHERE estado = 'Pendiente'
      AND fecha_vencimiento < CAST(GETDATE() AS date);

    SET @facturas_vencidas = @@ROWCOUNT;
END;
GO

--búsqueda de facturas por abonado, conexión, periodo o estado.
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarFacturas
    @tipo_abonado varchar(10) = NULL,
    @id_abonado   int         = NULL,
    @id_conexion  int         = NULL,
    @periodo      int         = NULL,   
    @estado       varchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.id_factura, s.id_conexion,
           dbo.fn_ObtenerNombreCompleto(c.id_abonado_fisico, c.id_abonado_juridico) AS abonado,
           l.fecha_lectura_actual, l.consumo,
           f.monto_fijo, f.monto_consumo, s.monto_total, s.recargos, s.pagado, s.saldo,
           s.fecha_emision, s.fecha_vencimiento, s.estado
    FROM dbo.vw_SaldoFactura s
    JOIN dbo.Factura  f ON f.id_factura = s.id_factura
    JOIN dbo.Lectura  l ON l.id_lectura = s.id_lectura
    JOIN dbo.Conexion c ON c.id_conexion = s.id_conexion
    WHERE (@id_conexion IS NULL OR s.id_conexion = @id_conexion)
      AND (@estado      IS NULL OR s.estado = @estado)
      AND (@periodo     IS NULL OR dbo.fn_ObtenerPeriodoFiscal(l.fecha_lectura_actual) = @periodo)
      AND (@id_abonado  IS NULL
           OR (@tipo_abonado = 'FISICO'   AND c.id_abonado_fisico   = @id_abonado)
           OR (@tipo_abonado = 'JURIDICO' AND c.id_abonado_juridico = @id_abonado))
    ORDER BY s.fecha_emision DESC;
END;
GO
