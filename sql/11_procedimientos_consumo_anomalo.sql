SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Script 11: Procedimientos - Detección de consumos anómalos (R9)
   ===================================================================== */
USE ASADA;
GO

-- Evalúa una lectura contra las reglas activas. Si varias reglas se cumplen,
-- se genera una sola alerta con la regla más exigente (mayor porcentaje).
-- La alerta no asume que hay una fuga: queda abierta para revisión.
CREATE OR ALTER PROCEDURE dbo.sp_DetectarConsumoAnomalo
    @id_lectura int,
    @id_alerta  int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id_medidor int, @fecha datetime, @consumo decimal(10,2);

    SELECT @id_medidor = id_medidor, @fecha = fecha_lectura_actual, @consumo = consumo
    FROM dbo.Lectura WHERE id_lectura = @id_lectura;

    IF @id_medidor IS NULL RETURN;

    -- Ya existe una alerta para esta lectura.
    IF EXISTS (SELECT 1 FROM dbo.Alerta_Consumo WHERE id_lectura = @id_lectura) RETURN;

    ;WITH evaluacion AS (
        SELECT r.id_regla_consumo, r.porcentaje_variacion AS umbral, r.consumo_minimo,
               dbo.fn_CalcularPromedioConsumo(@id_medidor, r.meses_promedio, @fecha) AS promedio
        FROM dbo.Regla_consumo r
        WHERE r.activo = 1
    )
    INSERT INTO dbo.Alerta_Consumo (id_regla_consumo, id_lectura, consumo_promedio, consumo_actual, porcentaje_variacion)
    SELECT TOP (1)
        e.id_regla_consumo, @id_lectura, ISNULL(e.promedio, 0), @consumo,
        dbo.fn_CalcularPorcentajeVariacion(e.promedio, @consumo)
    FROM evaluacion e
    WHERE dbo.fn_EsConsumoAnomalo(e.promedio, @consumo, e.umbral, e.consumo_minimo) = 1
    ORDER BY e.umbral DESC;

    IF @@ROWCOUNT > 0
        SET @id_alerta = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarAlertasConsumo
    @id_medidor        int         = NULL,
    @id_regla_consumo  int         = NULL,
    @estado            varchar(10) = NULL,
    @desde             date        = NULL,
    @hasta             date        = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.id_alerta, a.estado, n.nombre_nivel AS nivel, r.nombre_regla,
           m.id_medidor, m.numero_serie, m.id_conexion,
           l.fecha_lectura_actual, l.lectura_anterior, l.lectura_actual,
           a.consumo_promedio, a.consumo_actual, a.porcentaje_variacion,
           a.fecha_deteccion, a.fecha_resolucion, a.id_incidencia, a.observacion
    FROM dbo.Alerta_Consumo a
    JOIN dbo.Regla_consumo        r ON r.id_regla_consumo = a.id_regla_consumo
    JOIN dbo.Nivel_alerta_Consumo n ON n.id_nivel_alerta = r.id_nivel_alerta
    JOIN dbo.Lectura              l ON l.id_lectura = a.id_lectura
    JOIN dbo.Medidor              m ON m.id_medidor = l.id_medidor
    WHERE (@id_medidor       IS NULL OR m.id_medidor = @id_medidor)
      AND (@id_regla_consumo IS NULL OR a.id_regla_consumo = @id_regla_consumo)
      AND (@estado           IS NULL OR a.estado = @estado)
      AND (@desde            IS NULL OR a.fecha_deteccion >= @desde)
      AND (@hasta            IS NULL OR a.fecha_deteccion <= @hasta)
    ORDER BY a.fecha_deteccion DESC, a.id_alerta DESC;
END;
GO

-- Cambia el estado de la alerta y mantiene coherente la fecha de resolución.
-- Opcionalmente la vincula con una incidencia confirmada.
CREATE OR ALTER PROCEDURE dbo.sp_ActualizarEstadoAlertaConsumo
    @id_alerta      int,
    @estado         varchar(10),
    @observacion    varchar(4000) = NULL,
    @id_incidencia  int           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @estado NOT IN ('Abierta', 'Resuelta')
        THROW 50701, 'Estado no válido. Use: Abierta o Resuelta.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Alerta_Consumo WHERE id_alerta = @id_alerta)
        THROW 50702, 'La alerta indicada no existe.', 1;

    IF @id_incidencia IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Incidencia WHERE id_incidencia = @id_incidencia)
        THROW 50703, 'La incidencia indicada no existe.', 1;

    UPDATE dbo.Alerta_Consumo
    SET estado           = @estado,
        fecha_resolucion = CASE WHEN @estado = 'Resuelta' THEN ISNULL(fecha_resolucion, CAST(GETDATE() AS date)) END,
        observacion      = CASE WHEN @observacion IS NULL THEN observacion
                                ELSE CONCAT(observacion + CHAR(13) + CHAR(10), FORMAT(GETDATE(), 'yyyy-MM-dd HH:mm'), ' - ', @observacion) END,
        id_incidencia    = ISNULL(@id_incidencia, id_incidencia)
    WHERE id_alerta = @id_alerta;
END;
GO

-- Registra o modifica una regla de detección validando sus parámetros.
CREATE OR ALTER PROCEDURE dbo.sp_GestionarReglaConsumo
    @id_nivel_alerta       int,
    @nombre_regla          varchar(50),
    @porcentaje_variacion  decimal(5,2),
    @meses_promedio        int,
    @consumo_minimo        decimal(10,2) = 0,
    @descripcion           varchar(250)  = NULL,
    @activo                bit           = 1,
    @id_regla_consumo      int           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Nivel_alerta_Consumo WHERE id_nivel_alerta = @id_nivel_alerta)
        THROW 50704, 'El nivel de alerta indicado no existe.', 1;

    IF @porcentaje_variacion <= 0
        THROW 50705, 'El porcentaje de variación debe ser mayor que cero.', 1;

    IF @meses_promedio NOT BETWEEN 1 AND 24
        THROW 50706, 'Los meses para el promedio deben estar entre 1 y 24.', 1;

    IF @consumo_minimo < 0
        THROW 50707, 'El consumo mínimo no puede ser negativo.', 1;

    IF @id_regla_consumo IS NULL
    BEGIN
        INSERT INTO dbo.Regla_consumo (id_nivel_alerta, nombre_regla, porcentaje_variacion, meses_promedio, consumo_minimo, descripcion, activo)
        VALUES (@id_nivel_alerta, @nombre_regla, @porcentaje_variacion, @meses_promedio, @consumo_minimo, @descripcion, @activo);
        SET @id_regla_consumo = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE dbo.Regla_consumo
        SET id_nivel_alerta = @id_nivel_alerta, nombre_regla = @nombre_regla,
            porcentaje_variacion = @porcentaje_variacion, meses_promedio = @meses_promedio,
            consumo_minimo = @consumo_minimo, descripcion = @descripcion, activo = @activo
        WHERE id_regla_consumo = @id_regla_consumo;

        IF @@ROWCOUNT = 0 THROW 50708, 'La regla indicada no existe.', 1;
    END
END;
GO
