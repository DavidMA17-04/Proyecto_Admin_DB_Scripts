SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Script 07: Procedimientos - Pagos y morosidad (R3)
   ===================================================================== */
USE ASADA;
GO

/* ---------------------------------------------------------------------
   12.6 Pago
   --------------------------------------------------------------------- */
-- Registra un pago. trg_ActualizarEstadoFactura marca la factura como pagada
-- cuando el saldo llega a cero.
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarPago
    @id_factura      int,
    @id_metodo_pago  int,
    @monto           decimal(10,2),
    @fecha_pago      date = NULL,
    @id_pago         int  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @saldo decimal(10,2), @estado varchar(10);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- UPDLOCK evita que dos cajeros paguen la misma factura al mismo tiempo.
        SELECT @estado = estado
        FROM dbo.Factura WITH (UPDLOCK, ROWLOCK)
        WHERE id_factura = @id_factura;

        IF @estado IS NULL
            THROW 50301, 'La factura indicada no existe.', 1;

        IF @estado = 'Pagada'
            THROW 50302, 'La factura ya está pagada.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.Metodo_Pago WHERE id_metodo_pago = @id_metodo_pago AND activo = 1)
            THROW 50303, 'El método de pago no existe o está desactivado.', 1;

        IF @monto IS NULL OR @monto <= 0
            THROW 50304, 'El monto del pago debe ser mayor que cero.', 1;

        SET @saldo = dbo.fn_CalcularSaldoPendiente(@id_factura);

        IF @monto > @saldo
            THROW 50305, 'El monto pagado excede el saldo pendiente de la factura.', 1;

        INSERT INTO dbo.Pago (id_factura, id_metodo_pago, fecha_pago, monto)
        VALUES (@id_factura, @id_metodo_pago, ISNULL(@fecha_pago, CAST(GETDATE() AS date)), @monto);

        SET @id_pago = SCOPE_IDENTITY();

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

-- Anula un pago registrado por error. La factura vuelve a Pendiente o Vencida
-- (lo recalcula trg_ActualizarEstadoFactura).
CREATE OR ALTER PROCEDURE dbo.sp_AnularPago
    @id_pago int,
    @motivo  varchar(250)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(@motivo), '') IS NULL
        THROW 50306, 'Debe indicar el motivo de la anulación.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Pago
        SET estado = 'Anulado', motivo_anulacion = @motivo
        WHERE id_pago = @id_pago AND estado = 'Aplicado';

        IF @@ROWCOUNT = 0
            THROW 50307, 'El pago no existe o ya estaba anulado.', 1;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

-- Estado de cuenta: pagos de un abonado, de una factura o en un rango de fechas.
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarHistorialPagos
    @tipo_abonado varchar(10) = NULL,
    @id_abonado   int         = NULL,
    @id_factura   int         = NULL,
    @desde        date        = NULL,
    @hasta        date        = NULL,
    @incluir_anulados bit     = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.id_pago, p.fecha_pago, p.monto, mp.nombre_metodo, p.estado, p.motivo_anulacion,
           p.id_factura, s.monto_total, s.saldo AS saldo_actual_factura,
           s.id_conexion,
           dbo.fn_ObtenerNombreCompleto(c.id_abonado_fisico, c.id_abonado_juridico) AS abonado
    FROM dbo.Pago p
    JOIN dbo.Metodo_Pago     mp ON mp.id_metodo_pago = p.id_metodo_pago
    JOIN dbo.vw_SaldoFactura s  ON s.id_factura = p.id_factura
    JOIN dbo.Conexion        c  ON c.id_conexion = s.id_conexion
    WHERE (@id_factura IS NULL OR p.id_factura = @id_factura)
      AND (@desde      IS NULL OR p.fecha_pago >= @desde)
      AND (@hasta      IS NULL OR p.fecha_pago <= @hasta)
      AND (@incluir_anulados = 1 OR p.estado = 'Aplicado')
      AND (@id_abonado IS NULL
           OR (@tipo_abonado = 'FISICO'   AND c.id_abonado_fisico   = @id_abonado)
           OR (@tipo_abonado = 'JURIDICO' AND c.id_abonado_juridico = @id_abonado))
    ORDER BY p.fecha_pago DESC, p.id_pago DESC;
END;
GO

/* ---------------------------------------------------------------------
   12.15 Recargo por mora
   --------------------------------------------------------------------- */
-- Calcula el recargo de una factura vencida sobre el saldo sin recargos.
-- Cada factura tiene como máximo un recargo vigente: si ya existía uno se anula
-- y se reemplaza (recalculo por pago parcial o por más días de atraso).
CREATE OR ALTER PROCEDURE dbo.sp_CalcularRecargoMora
    @id_factura  int,
    @fecha_corte date = NULL,
    @id_recargo  int  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @vencimiento date, @estado varchar(10), @dias int, @porcentaje decimal(5,2),
            @saldo_base decimal(10,2), @porcentaje_vigente decimal(5,2), @monto_vigente decimal(10,2),
            @monto_nuevo decimal(10,2);

    SET @fecha_corte = ISNULL(@fecha_corte, CAST(GETDATE() AS date));

    SELECT @vencimiento = fecha_vencimiento, @estado = estado
    FROM dbo.Factura WHERE id_factura = @id_factura;

    IF @vencimiento IS NULL
        THROW 50301, 'La factura indicada no existe.', 1;

    IF @estado = 'Pagada'
        THROW 50302, 'La factura ya está pagada.', 1;

    SET @dias = DATEDIFF(DAY, @vencimiento, @fecha_corte);
    IF @dias <= 0
        THROW 50308, 'La factura todavía no está vencida.', 1;

    -- Saldo sin recargos = total - pagos aplicados
    SELECT @saldo_base = s.monto_total - s.pagado FROM dbo.vw_SaldoFactura s WHERE s.id_factura = @id_factura;
    IF @saldo_base <= 0
        THROW 50309, 'La factura no tiene saldo sobre el cual aplicar recargo.', 1;

    SET @porcentaje  = dbo.fn_CalcularPorcentajeMora(@dias);
    SET @monto_nuevo = ROUND(@saldo_base * @porcentaje / 100.0, 2);

    SELECT @porcentaje_vigente = porcentaje_aplicado, @monto_vigente = monto_recargo
    FROM dbo.Recargo_mora
    WHERE id_factura = @id_factura AND estado = 'Aplicado';

    -- Si el recargo vigente ya es el correcto, no se hace nada.
    IF @porcentaje_vigente = @porcentaje AND @monto_vigente = @monto_nuevo
    BEGIN
        SELECT @id_recargo = id_recargo FROM dbo.Recargo_mora WHERE id_factura = @id_factura AND estado = 'Aplicado';
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Recargo_mora
        SET estado = 'Anulado', motivo_anulacion = 'Recalculado por cambio en días de atraso o en el saldo'
        WHERE id_factura = @id_factura AND estado = 'Aplicado';

        INSERT INTO dbo.Recargo_mora (id_factura, fecha_calculo, porcentaje_aplicado, monto_recargo)
        VALUES (@id_factura, GETDATE(), @porcentaje, @monto_nuevo);

        SET @id_recargo = SCOPE_IDENTITY();

        UPDATE dbo.Factura
        SET estado = 'Vencida', fecha_modificacion = GETDATE()
        WHERE id_factura = @id_factura AND estado <> 'Vencida';

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO

-- Aplica el recargo a todas las facturas vencidas con saldo, en un solo proceso.
CREATE OR ALTER PROCEDURE dbo.sp_AplicarRecargosMoraMasivo
    @fecha_corte          date = NULL,
    @recargos_procesados  int  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id_factura int;
    DECLARE @errores TABLE (id_factura int, mensaje nvarchar(4000));
    SET @fecha_corte = ISNULL(@fecha_corte, CAST(GETDATE() AS date));
    SET @recargos_procesados = 0;

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT id_factura
        FROM dbo.vw_SaldoFactura
        WHERE estado IN ('Pendiente', 'Vencida')
          AND fecha_vencimiento < @fecha_corte
          AND monto_total - pagado > 0;

    OPEN cur;
    FETCH NEXT FROM cur INTO @id_factura;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC dbo.sp_CalcularRecargoMora @id_factura = @id_factura, @fecha_corte = @fecha_corte;
            SET @recargos_procesados += 1;
        END TRY
        BEGIN CATCH
            INSERT INTO @errores VALUES (@id_factura, ERROR_MESSAGE());
        END CATCH
        FETCH NEXT FROM cur INTO @id_factura;
    END
    CLOSE cur;
    DEALLOCATE cur;

    SELECT @recargos_procesados AS facturas_procesadas;
    IF EXISTS (SELECT 1 FROM @errores)
        SELECT * FROM @errores;
END;
GO

-- Revierte un recargo aplicado por error o por resolución administrativa.
CREATE OR ALTER PROCEDURE dbo.sp_AnularRecargoMora
    @id_recargo int,
    @motivo     varchar(250)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(@motivo), '') IS NULL
        THROW 50306, 'Debe indicar el motivo de la anulación.', 1;

    UPDATE dbo.Recargo_mora
    SET estado = 'Anulado', motivo_anulacion = @motivo
    WHERE id_recargo = @id_recargo AND estado = 'Aplicado';

    IF @@ROWCOUNT = 0
        THROW 50310, 'El recargo no existe o ya estaba anulado.', 1;
END;
GO

-- R3-02: prórroga de una factura. Mueve la fecha de vencimiento y anula el recargo vigente.
CREATE OR ALTER PROCEDURE dbo.sp_OtorgarProrroga
    @id_factura              int,
    @nueva_fecha_vencimiento date,
    @motivo                  varchar(250)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado varchar(10), @vencimiento date;
    SELECT @estado = estado, @vencimiento = fecha_vencimiento FROM dbo.Factura WHERE id_factura = @id_factura;

    IF @estado IS NULL
        THROW 50301, 'La factura indicada no existe.', 1;
    IF @estado = 'Pagada'
        THROW 50302, 'La factura ya está pagada.', 1;
    IF @nueva_fecha_vencimiento <= @vencimiento OR @nueva_fecha_vencimiento < CAST(GETDATE() AS date)
        THROW 50311, 'La nueva fecha de vencimiento debe ser posterior a la actual y a la fecha de hoy.', 1;
    IF NULLIF(LTRIM(@motivo), '') IS NULL
        THROW 50306, 'Debe indicar el motivo de la prórroga.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Recargo_mora
        SET estado = 'Anulado', motivo_anulacion = CONCAT('Prórroga: ', @motivo)
        WHERE id_factura = @id_factura AND estado = 'Aplicado';

        UPDATE dbo.Factura
        SET fecha_vencimiento = @nueva_fecha_vencimiento, estado = 'Pendiente', fecha_modificacion = GETDATE()
        WHERE id_factura = @id_factura;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
