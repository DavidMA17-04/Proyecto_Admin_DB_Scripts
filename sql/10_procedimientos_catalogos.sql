SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Script 10: Procedimientos - Tarifas y catálogos
   Los procedimientos "Gestionar" registran cuando el id es NULL y
   modifican cuando el id viene informado.
   ===================================================================== */
USE ASADA;
GO

/* ---------------------------------------------------------------------
   12.13 Tarifa
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarTarifa
    @id_tipo_tarifa int,
    @monto_fijo     decimal(10,2),
    @monto_por_m3   decimal(10,2),
    @id_tarifa      int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF dbo.fn_TipoTarifaActivo(@id_tipo_tarifa) = 0
        THROW 50601, 'El tipo de tarifa no existe o está inactivo.', 1;

    IF @monto_fijo <= 0 OR @monto_por_m3 <= 0
        THROW 50602, 'El monto fijo y el monto por m³ deben ser mayores que cero.', 1;

    INSERT INTO dbo.Tarifa (id_tipo_tarifa, monto_fijo, monto_por_m3)
    VALUES (@id_tipo_tarifa, @monto_fijo, @monto_por_m3);

    SET @id_tarifa = SCOPE_IDENTITY();
END;
GO

-- Actualiza los montos. trg_AuditarTarifa guarda el cambio en Historial_Tarifa.
CREATE OR ALTER PROCEDURE dbo.sp_ModificarTarifa
    @id_tarifa    int,
    @monto_fijo   decimal(10,2) = NULL,
    @monto_por_m3 decimal(10,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Tarifa WHERE id_tarifa = @id_tarifa AND activo = 1)
        THROW 50603, 'La tarifa no existe o está inactiva.', 1;

    IF @monto_fijo <= 0 OR @monto_por_m3 <= 0
        THROW 50602, 'El monto fijo y el monto por m³ deben ser mayores que cero.', 1;

    UPDATE dbo.Tarifa
    SET monto_fijo   = ISNULL(@monto_fijo, monto_fijo),
        monto_por_m3 = ISNULL(@monto_por_m3, monto_por_m3)
    WHERE id_tarifa = @id_tarifa;
END;
GO

-- Baja lógica. No se permite si hay conexiones activas usando la tarifa.
CREATE OR ALTER PROCEDURE dbo.sp_DesactivarTarifa
    @id_tarifa int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Conexion WHERE id_tarifa = @id_tarifa AND estado = 'Activa')
        THROW 50604, 'No se puede desactivar: hay conexiones activas con esta tarifa.', 1;

    UPDATE dbo.Tarifa SET activo = 0 WHERE id_tarifa = @id_tarifa AND activo = 1;

    IF @@ROWCOUNT = 0
        THROW 50603, 'La tarifa no existe o ya estaba inactiva.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarTarifas
    @id_tipo_tarifa int = NULL,
    @solo_activas   bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT t.id_tarifa, tt.nombre_tarifa AS tipo_tarifa, t.monto_fijo, t.monto_por_m3, t.activo,
           (SELECT COUNT(*) FROM dbo.Conexion c WHERE c.id_tarifa = t.id_tarifa AND c.estado = 'Activa') AS conexiones_activas
    FROM dbo.Tarifa t
    JOIN dbo.Tipo_Tarifa tt ON tt.id_tipo_tarifa = t.id_tipo_tarifa
    WHERE (@id_tipo_tarifa IS NULL OR t.id_tipo_tarifa = @id_tipo_tarifa)
      AND (@solo_activas = 0 OR t.activo = 1)
    ORDER BY tt.nombre_tarifa, t.id_tarifa;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarHistorialTarifa
    @id_tarifa int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT h.id_historial_tarifa, h.fecha_cambio,
           h.monto_fijo_anterior, h.monto_fijo_nuevo,
           h.monto_por_m3_anterior, h.monto_por_m3_nuevo,
           ISNULL(u.nombre_usuario, 'SISTEMA') AS usuario
    FROM dbo.Historial_Tarifa h
    LEFT JOIN dbo.Usuario_Sistema u ON u.id_usuario_sistema = h.id_usuario_sistema
    WHERE h.id_tarifa = @id_tarifa
    ORDER BY h.fecha_cambio DESC;
END;
GO

-- Compara cuánto pagaría un abonado con la tarifa actual y con una propuesta.
CREATE OR ALTER PROCEDURE dbo.sp_SimularMontoConTarifa
    @consumo_m3              decimal(10,2),
    @monto_fijo_propuesto    decimal(10,2),
    @monto_por_m3_propuesto  decimal(10,2),
    @id_tarifa_actual        int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @monto_actual decimal(10,2) = NULL;

    IF @consumo_m3 < 0 OR @monto_fijo_propuesto <= 0 OR @monto_por_m3_propuesto <= 0
        THROW 50605, 'El consumo no puede ser negativo y los montos propuestos deben ser mayores que cero.', 1;

    SELECT @monto_actual = dbo.fn_CalcularMontoFactura(@consumo_m3, monto_fijo, monto_por_m3)
    FROM dbo.Tarifa WHERE id_tarifa = @id_tarifa_actual;

    DECLARE @monto_propuesto decimal(10,2) = dbo.fn_CalcularMontoFactura(@consumo_m3, @monto_fijo_propuesto, @monto_por_m3_propuesto);

    SELECT @consumo_m3      AS consumo_m3,
           @monto_actual    AS monto_tarifa_actual,
           @monto_propuesto AS monto_tarifa_propuesta,
           @monto_propuesto - @monto_actual AS diferencia,
           CASE WHEN @monto_actual > 0
                THEN CAST((@monto_propuesto - @monto_actual) * 100.0 / @monto_actual AS decimal(7,2)) END AS variacion_porcentual;
END;
GO

/* ---------------------------------------------------------------------
   12.14 Tipo de tarifa
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_GestionarTipoTarifa
    @nombre_tarifa  varchar(15),
    @activo         bit = 1,
    @id_tipo_tarifa int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Tipo_Tarifa
               WHERE nombre_tarifa = @nombre_tarifa AND (@id_tipo_tarifa IS NULL OR id_tipo_tarifa <> @id_tipo_tarifa))
        THROW 50606, 'Ya existe un tipo de tarifa con ese nombre.', 1;

    IF @id_tipo_tarifa IS NULL
    BEGIN
        INSERT INTO dbo.Tipo_Tarifa (nombre_tarifa, activo) VALUES (@nombre_tarifa, @activo);
        SET @id_tipo_tarifa = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        IF @activo = 0 AND EXISTS (SELECT 1 FROM dbo.Tarifa WHERE id_tipo_tarifa = @id_tipo_tarifa AND activo = 1)
            THROW 50607, 'No se puede desactivar: el tipo tiene tarifas activas.', 1;

        UPDATE dbo.Tipo_Tarifa SET nombre_tarifa = @nombre_tarifa, activo = @activo WHERE id_tipo_tarifa = @id_tipo_tarifa;
        IF @@ROWCOUNT = 0 THROW 50601, 'El tipo de tarifa no existe.', 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarTiposTarifa
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_tipo_tarifa, nombre_tarifa FROM dbo.Tipo_Tarifa WHERE activo = 1 ORDER BY nombre_tarifa;
END;
GO

/* ---------------------------------------------------------------------
   12.17 Nivel de alerta de consumo
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_GestionarNivelAlerta
    @nombre_nivel    varchar(50),
    @id_nivel_alerta int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Nivel_alerta_Consumo
               WHERE nombre_nivel = @nombre_nivel AND (@id_nivel_alerta IS NULL OR id_nivel_alerta <> @id_nivel_alerta))
        THROW 50608, 'Ya existe un nivel de alerta con ese nombre.', 1;

    IF @id_nivel_alerta IS NULL
    BEGIN
        INSERT INTO dbo.Nivel_alerta_Consumo (nombre_nivel) VALUES (@nombre_nivel);
        SET @id_nivel_alerta = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE dbo.Nivel_alerta_Consumo SET nombre_nivel = @nombre_nivel WHERE id_nivel_alerta = @id_nivel_alerta;
        IF @@ROWCOUNT = 0 THROW 50609, 'El nivel de alerta no existe.', 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarNivelesAlerta
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_nivel_alerta, nombre_nivel FROM dbo.Nivel_alerta_Consumo ORDER BY id_nivel_alerta;
END;
GO

/* ---------------------------------------------------------------------
   12.16 Regla de consumo (consulta). La gestión está en el script 11.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarReglasConsumo
    @solo_activas bit = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.id_regla_consumo, r.nombre_regla, n.nombre_nivel, r.porcentaje_variacion,
           r.meses_promedio, r.consumo_minimo, r.descripcion, r.activo, r.fecha_creacion
    FROM dbo.Regla_consumo r
    JOIN dbo.Nivel_alerta_Consumo n ON n.id_nivel_alerta = r.id_nivel_alerta
    WHERE @solo_activas = 0 OR r.activo = 1
    ORDER BY r.porcentaje_variacion;
END;
GO

/* ---------------------------------------------------------------------
   12.18 Tipo de trabajo
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_GestionarTipoTrabajo
    @nombre_trabajo  varchar(15),
    @activo          bit = 1,
    @id_tipo_trabajo int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Tipo_Trabajo
               WHERE nombre_trabajo = @nombre_trabajo AND (@id_tipo_trabajo IS NULL OR id_tipo_trabajo <> @id_tipo_trabajo))
        THROW 50610, 'Ya existe un tipo de trabajo con ese nombre.', 1;

    IF @id_tipo_trabajo IS NULL
    BEGIN
        INSERT INTO dbo.Tipo_Trabajo (nombre_trabajo, activo) VALUES (@nombre_trabajo, @activo);
        SET @id_tipo_trabajo = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE dbo.Tipo_Trabajo SET nombre_trabajo = @nombre_trabajo, activo = @activo WHERE id_tipo_trabajo = @id_tipo_trabajo;
        IF @@ROWCOUNT = 0 THROW 50611, 'El tipo de trabajo no existe.', 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarTiposTrabajo
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_tipo_trabajo, nombre_trabajo FROM dbo.Tipo_Trabajo WHERE activo = 1 ORDER BY nombre_trabajo;
END;
GO

/* ---------------------------------------------------------------------
   12.21 Método de pago
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_GestionarMetodoPago
    @nombre_metodo  varchar(50),
    @id_metodo_pago int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Metodo_Pago
               WHERE nombre_metodo = @nombre_metodo AND (@id_metodo_pago IS NULL OR id_metodo_pago <> @id_metodo_pago))
        THROW 50612, 'Ya existe un método de pago con ese nombre.', 1;

    IF @id_metodo_pago IS NULL
    BEGIN
        INSERT INTO dbo.Metodo_Pago (nombre_metodo) VALUES (@nombre_metodo);
        SET @id_metodo_pago = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE dbo.Metodo_Pago SET nombre_metodo = @nombre_metodo WHERE id_metodo_pago = @id_metodo_pago;
        IF @@ROWCOUNT = 0 THROW 50613, 'El método de pago no existe.', 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarMetodosPago
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_metodo_pago, nombre_metodo FROM dbo.vw_MetodosPagoActivos ORDER BY nombre_metodo;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_DesactivarMetodoPago
    @id_metodo_pago int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    UPDATE dbo.Metodo_Pago SET activo = 0 WHERE id_metodo_pago = @id_metodo_pago AND activo = 1;

    IF @@ROWCOUNT = 0
        THROW 50613, 'El método de pago no existe o ya estaba desactivado.', 1;
END;
GO

/* ---------------------------------------------------------------------
   12.29 Tipo de incidencia
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_GestionarTipoIncidencia
    @nombre_incidencia  varchar(20),
    @activo             bit = 1,
    @id_tipo_incidencia int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Tipo_Incidencia
               WHERE nombre_incidencia = @nombre_incidencia AND (@id_tipo_incidencia IS NULL OR id_tipo_incidencia <> @id_tipo_incidencia))
        THROW 50614, 'Ya existe un tipo de incidencia con ese nombre.', 1;

    IF @id_tipo_incidencia IS NULL
    BEGIN
        INSERT INTO dbo.Tipo_Incidencia (nombre_incidencia, activo) VALUES (@nombre_incidencia, @activo);
        SET @id_tipo_incidencia = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE dbo.Tipo_Incidencia SET nombre_incidencia = @nombre_incidencia, activo = @activo
        WHERE id_tipo_incidencia = @id_tipo_incidencia;
        IF @@ROWCOUNT = 0 THROW 50615, 'El tipo de incidencia no existe.', 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarTiposIncidencia
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_tipo_incidencia, nombre_incidencia FROM dbo.Tipo_Incidencia WHERE activo = 1 ORDER BY nombre_incidencia;
END;
GO

/* ---------------------------------------------------------------------
   12.23 Tipo de respaldo
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_GestionarTipoRespaldo
    @nombre_respaldo  varchar(15),
    @id_tipo_respaldo int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @nombre_respaldo NOT IN ('Completo', 'Diferencial', 'Log')
        THROW 50616, 'Tipo no válido. Use: Completo, Diferencial o Log.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Tipo_Respaldo
               WHERE nombre_respaldo = @nombre_respaldo AND (@id_tipo_respaldo IS NULL OR id_tipo_respaldo <> @id_tipo_respaldo))
        THROW 50617, 'Ese tipo de respaldo ya está registrado.', 1;

    IF @id_tipo_respaldo IS NULL
    BEGIN
        INSERT INTO dbo.Tipo_Respaldo (nombre_respaldo) VALUES (@nombre_respaldo);
        SET @id_tipo_respaldo = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE dbo.Tipo_Respaldo SET nombre_respaldo = @nombre_respaldo WHERE id_tipo_respaldo = @id_tipo_respaldo;
        IF @@ROWCOUNT = 0 THROW 50618, 'El tipo de respaldo no existe.', 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarTiposRespaldo
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_tipo_respaldo, nombre_respaldo FROM dbo.Tipo_Respaldo ORDER BY id_tipo_respaldo;
END;
GO
