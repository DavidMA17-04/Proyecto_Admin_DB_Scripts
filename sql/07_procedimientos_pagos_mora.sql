SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Script 07: Procedimientos - Pagos y morosidad 
   --------------------------------------------------------------------*/
USE ASADA;
GO

   --Pago
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

    DECLARE @saldo decimal(10,2), @estado varchar(10), @fecha_emision datetime;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- UPDLOCK evita que dos cajeros paguen la misma factura al mismo tiempo.
        SELECT @estado = estado, @fecha_emision = fecha_emision
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

        SET @fecha_pago = ISNULL(@fecha_pago, CAST(GETDATE() AS date));

        IF @fecha_pago > CAST(GETDATE() AS date)
            THROW 50312, 'La fecha del pago no puede ser futura.', 1;

        IF @fecha_pago < CAST(@fecha_emision AS date)
            THROW 50313, 'La fecha del pago no puede ser anterior a la fecha de emisión de la factura.', 1;

        SET @saldo = dbo.fn_CalcularSaldoPendiente(@id_factura);

        IF @monto > @saldo
            THROW 50305, 'El monto pagado excede el saldo pendiente de la factura.', 1;

        INSERT INTO dbo.Pago (id_factura, id_metodo_pago, fecha_pago, monto)
        VALUES (@id_factura, @id_metodo_pago, @fecha_pago, @monto);

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

   --Recargo por mora
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

    -- Si un administrador anuló el recargo de esta factura, no se vuelve a aplicar.
    IF EXISTS (SELECT 1 FROM dbo.Recargo_mora WHERE id_factura = @id_factura AND anulado_manual = 1)
        THROW 50314, 'El recargo de esta factura fue anulado manualmente y no se recalcula automáticamente.', 1;

    SELECT @vencimiento = fecha_vencimiento, @estado = estado
    FROM dbo.Factura WITH (UPDLOCK, ROWLOCK)
    WHERE id_factura = @id_factura;

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
    IF @porcentaje IS NULL OR @porcentaje <= 0
        THROW 50315, 'No hay un tramo de mora configurado para esos días de atraso.', 1;

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
        FROM dbo.vw_SaldoFactura s
        WHERE estado IN ('Pendiente', 'Vencida')
          AND fecha_vencimiento < @fecha_corte
          AND monto_total - pagado > 0
          -- Respeta los recargos que un administrador anuló a mano.
          AND NOT EXISTS (SELECT 1 FROM dbo.Recargo_mora rm
                          WHERE rm.id_factura = s.id_factura AND rm.anulado_manual = 1);

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
-- Queda marcado como anulación manual para que el proceso automático no lo repita.
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
    SET estado = 'Anulado', motivo_anulacion = @motivo, anulado_manual = 1
    WHERE id_recargo = @id_recargo AND estado = 'Aplicado';

    IF @@ROWCOUNT = 0
        THROW 50310, 'El recargo no existe o ya estaba anulado.', 1;
END;
GO

--prórroga de una factura. Mueve la fecha de vencimiento y anula el recargo vigente.
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

   --Estado de cuenta del abonado
-- Devuelve cuatro resultados: resumen, facturas, pagos y recargos del abonado.
CREATE OR ALTER PROCEDURE dbo.sp_EstadoCuentaAbonado
    @tipo_abonado varchar(10),
    @id_abonado   int,
    @fecha_corte  date = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @fecha_corte = ISNULL(@fecha_corte, CAST(GETDATE() AS date));
    SET @tipo_abonado = UPPER(LTRIM(RTRIM(@tipo_abonado)));

    IF @tipo_abonado NOT IN ('FISICO', 'JURIDICO')
        THROW 50320, 'El tipo de abonado debe ser FISICO o JURIDICO.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.vw_Abonados
                   WHERE tipo_abonado = @tipo_abonado AND id_abonado = @id_abonado)
        THROW 50321, 'El abonado indicado no existe.', 1;

    CREATE TABLE #conexiones (id_conexion int NOT NULL PRIMARY KEY);

    INSERT INTO #conexiones (id_conexion)
    SELECT c.id_conexion
    FROM dbo.Conexion c
    WHERE (@tipo_abonado = 'FISICO'   AND c.id_abonado_fisico   = @id_abonado)
       OR (@tipo_abonado = 'JURIDICO' AND c.id_abonado_juridico = @id_abonado);

    -- 1) Resumen
    SELECT a.tipo_abonado, a.identificacion, a.nombre_completo, a.direccion, a.telefono,
           @fecha_corte AS fecha_corte,
           (SELECT COUNT(*) FROM #conexiones) AS conexiones,
           (SELECT COUNT(*) FROM dbo.Conexion c JOIN #conexiones x ON x.id_conexion = c.id_conexion
             WHERE c.estado = 'Activa') AS conexiones_activas,
           ISNULL((SELECT SUM(s.monto_total) FROM dbo.vw_SaldoFactura s
                    JOIN #conexiones x ON x.id_conexion = s.id_conexion), 0) AS total_facturado,
           ISNULL((SELECT SUM(s.recargos) FROM dbo.vw_SaldoFactura s
                    JOIN #conexiones x ON x.id_conexion = s.id_conexion), 0) AS total_recargos,
           ISNULL((SELECT SUM(s.pagado) FROM dbo.vw_SaldoFactura s
                    JOIN #conexiones x ON x.id_conexion = s.id_conexion), 0) AS total_pagado,
           ISNULL((SELECT SUM(s.saldo) FROM dbo.vw_SaldoFactura s
                    JOIN #conexiones x ON x.id_conexion = s.id_conexion
                    WHERE s.saldo > 0), 0) AS saldo_pendiente,
           (SELECT COUNT(*) FROM dbo.vw_SaldoFactura s
             JOIN #conexiones x ON x.id_conexion = s.id_conexion
             WHERE s.saldo > 0) AS facturas_pendientes,
           (SELECT COUNT(*) FROM dbo.vw_SaldoFactura s
             JOIN #conexiones x ON x.id_conexion = s.id_conexion
             WHERE s.saldo > 0 AND s.fecha_vencimiento < @fecha_corte) AS facturas_vencidas,
           ISNULL((SELECT SUM(s.saldo) FROM dbo.vw_SaldoFactura s
                    JOIN #conexiones x ON x.id_conexion = s.id_conexion
                    WHERE s.saldo > 0 AND s.fecha_vencimiento < @fecha_corte), 0) AS saldo_vencido,
           ISNULL((SELECT MAX(DATEDIFF(DAY, s.fecha_vencimiento, @fecha_corte))
                     FROM dbo.vw_SaldoFactura s
                     JOIN #conexiones x ON x.id_conexion = s.id_conexion
                     WHERE s.saldo > 0 AND s.fecha_vencimiento < @fecha_corte), 0) AS dias_atraso_maximo
    FROM dbo.vw_Abonados a
    WHERE a.tipo_abonado = @tipo_abonado AND a.id_abonado = @id_abonado;

    -- 2) Facturas
    SELECT s.id_factura, s.id_conexion, s.fecha_emision, s.fecha_vencimiento,
           s.monto_total, s.recargos, s.pagado, s.saldo, s.estado,
           CASE WHEN s.saldo > 0 AND s.fecha_vencimiento < @fecha_corte
                THEN DATEDIFF(DAY, s.fecha_vencimiento, @fecha_corte) ELSE 0 END AS dias_atraso
    FROM dbo.vw_SaldoFactura s
    JOIN #conexiones x ON x.id_conexion = s.id_conexion
    ORDER BY s.fecha_vencimiento DESC, s.id_factura DESC;

    -- 3) Pagos
    SELECT p.id_pago, p.id_factura, p.fecha_pago, p.monto, mp.nombre_metodo,
           p.estado, p.motivo_anulacion
    FROM dbo.Pago p
    JOIN dbo.Metodo_Pago mp ON mp.id_metodo_pago = p.id_metodo_pago
    JOIN dbo.Factura f      ON f.id_factura = p.id_factura
    JOIN dbo.Lectura l      ON l.id_lectura = f.id_lectura
    JOIN dbo.Medidor m      ON m.id_medidor = l.id_medidor
    JOIN #conexiones x      ON x.id_conexion = m.id_conexion
    ORDER BY p.fecha_pago DESC, p.id_pago DESC;

    -- 4) Recargos
    SELECT r.id_recargo, r.id_factura, r.fecha_calculo, r.porcentaje_aplicado, r.monto_recargo,
           r.estado, r.motivo_anulacion
    FROM dbo.Recargo_mora r
    JOIN dbo.Factura f ON f.id_factura = r.id_factura
    JOIN dbo.Lectura l ON l.id_lectura = f.id_lectura
    JOIN dbo.Medidor m ON m.id_medidor = l.id_medidor
    JOIN #conexiones x ON x.id_conexion = m.id_conexion
    ORDER BY r.fecha_calculo DESC, r.id_recargo DESC;
END;
GO

   --Suspensión y reactivación por morosidad
-- Suspende las conexiones activas que superan los límites configurados.
-- Con @solo_simular = 1 solo devuelve el listado, sin cambiar estados.
CREATE OR ALTER PROCEDURE dbo.sp_SuspenderConexionesMorosas
    @dias_minimos int           = NULL,
    @saldo_minimo decimal(12,2) = NULL,
    @solo_simular bit           = 0,
    @suspendidas  int           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @corte date = CAST(GETDATE() AS date);
    DECLARE @id int;
    DECLARE @afectadas TABLE (
        id_conexion    int           NOT NULL PRIMARY KEY,
        abonado        varchar(152)  NULL,
        saldo_vencido  decimal(12,2) NOT NULL,
        dias_atraso    int           NOT NULL
    );

    IF @dias_minimos IS NULL
        SELECT @dias_minimos = CAST(valor AS int) FROM dbo.Parametro_Mora WHERE nombre = 'dias_mora_suspension';
    IF @saldo_minimo IS NULL
        SELECT @saldo_minimo = valor FROM dbo.Parametro_Mora WHERE nombre = 'saldo_minimo_suspension';

    SET @dias_minimos = ISNULL(@dias_minimos, 90);
    SET @saldo_minimo = ISNULL(@saldo_minimo, 0);

    INSERT INTO @afectadas (id_conexion, abonado, saldo_vencido, dias_atraso)
    SELECT c.id_conexion,
           dbo.fn_ObtenerNombreCompleto(c.id_abonado_fisico, c.id_abonado_juridico),
           SUM(s.saldo),
           MAX(DATEDIFF(DAY, s.fecha_vencimiento, @corte))
    FROM dbo.Conexion c
    JOIN dbo.vw_SaldoFactura s ON s.id_conexion = c.id_conexion
    WHERE c.estado = 'Activa'
      AND s.saldo > 0
      AND s.estado IN ('Pendiente', 'Vencida')
      AND s.fecha_vencimiento < @corte
    GROUP BY c.id_conexion, c.id_abonado_fisico, c.id_abonado_juridico
    HAVING MAX(DATEDIFF(DAY, s.fecha_vencimiento, @corte)) >= @dias_minimos
       AND SUM(s.saldo) >= @saldo_minimo;

    IF @solo_simular = 1
        SET @suspendidas = (SELECT COUNT(*) FROM @afectadas);
    ELSE
    BEGIN
        SET @suspendidas = 0;
        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT id_conexion FROM @afectadas;
        OPEN cur;
        FETCH NEXT FROM cur INTO @id;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                EXEC dbo.sp_CambiarEstadoConexion
                     @id_conexion = @id,
                     @nuevo_estado = 'Suspendida',
                     @motivo = 'Suspensión automática por morosidad';
                SET @suspendidas += 1;
            END TRY
            BEGIN CATCH
                -- Si una conexión falla, se continúa con las demás.
            END CATCH
            FETCH NEXT FROM cur INTO @id;
        END
        CLOSE cur;
        DEALLOCATE cur;
    END

    SELECT @suspendidas AS conexiones_suspendidas,
           @dias_minimos AS dias_minimos,
           @saldo_minimo AS saldo_minimo,
           @corte        AS fecha_corte;

    SELECT id_conexion, abonado, saldo_vencido, dias_atraso
    FROM @afectadas
    ORDER BY saldo_vencido DESC;
END;
GO

-- Reactiva las conexiones suspendidas que ya no tienen saldo vencido.
CREATE OR ALTER PROCEDURE dbo.sp_ReactivarConexionesSinMora
    @solo_simular bit = 0,
    @reactivadas  int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @corte date = CAST(GETDATE() AS date);
    DECLARE @id int;
    DECLARE @afectadas TABLE (id_conexion int NOT NULL PRIMARY KEY, abonado varchar(152) NULL);

    INSERT INTO @afectadas (id_conexion, abonado)
    SELECT c.id_conexion, dbo.fn_ObtenerNombreCompleto(c.id_abonado_fisico, c.id_abonado_juridico)
    FROM dbo.Conexion c
    WHERE c.estado = 'Suspendida'
      AND NOT EXISTS (
            SELECT 1
            FROM dbo.vw_SaldoFactura s
            WHERE s.id_conexion = c.id_conexion
              AND s.saldo > 0
              AND s.estado IN ('Pendiente', 'Vencida')
              AND s.fecha_vencimiento < @corte
      );

    IF @solo_simular = 1
        SET @reactivadas = (SELECT COUNT(*) FROM @afectadas);
    ELSE
    BEGIN
        SET @reactivadas = 0;
        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT id_conexion FROM @afectadas;
        OPEN cur;
        FETCH NEXT FROM cur INTO @id;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                EXEC dbo.sp_CambiarEstadoConexion
                     @id_conexion = @id,
                     @nuevo_estado = 'Activa',
                     @motivo = 'Reactivación automática: sin morosidad pendiente';
                SET @reactivadas += 1;
            END TRY
            BEGIN CATCH
                -- Si una conexión falla, se continúa con las demás.
            END CATCH
            FETCH NEXT FROM cur INTO @id;
        END
        CLOSE cur;
        DEALLOCATE cur;
    END

    SELECT @reactivadas AS conexiones_reactivadas, @corte AS fecha_corte;
    SELECT id_conexion, abonado FROM @afectadas ORDER BY abonado;
END;
GO

   --Configuración de morosidad
-- Cambia el valor de un parámetro existente.
CREATE OR ALTER PROCEDURE dbo.sp_GestionarParametroMora
    @nombre varchar(50),
    @valor  decimal(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Parametro_Mora
    SET valor = @valor, fecha_modificacion = GETDATE()
    WHERE nombre = @nombre;

    IF @@ROWCOUNT = 0
        THROW 50330, 'El parámetro indicado no existe.', 1;
END;
GO

-- Crea (@id_tramo NULL) o modifica un tramo de mora.
CREATE OR ALTER PROCEDURE dbo.sp_GestionarTramoMora
    @id_tramo         int = NULL,
    @dias_desde       int,
    @dias_hasta       int = NULL,
    @porcentaje       decimal(5,2),
    @activo           bit = 1,
    @id_tramo_salida  int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @porcentaje IS NULL OR @porcentaje <= 0 OR @porcentaje > 100
        THROW 50331, 'El porcentaje debe ser mayor que 0 y menor o igual a 100.', 1;

    IF @dias_desde IS NULL OR @dias_desde <= 0
       OR (@dias_hasta IS NOT NULL AND @dias_hasta < @dias_desde)
        THROW 50332, 'El rango de días no es válido.', 1;

    IF @activo = 1
       AND EXISTS (
            SELECT 1 FROM dbo.Tramo_Mora
            WHERE activo = 1
              AND id_tramo <> ISNULL(@id_tramo, 0)
              AND @dias_desde <= ISNULL(dias_hasta, 2147483647)
              AND dias_desde <= ISNULL(@dias_hasta, 2147483647))
        THROW 50333, 'El rango se superpone con otro tramo activo.', 1;

    IF @id_tramo IS NULL
    BEGIN
        INSERT INTO dbo.Tramo_Mora (dias_desde, dias_hasta, porcentaje, activo)
        VALUES (@dias_desde, @dias_hasta, @porcentaje, @activo);

        SET @id_tramo_salida = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE dbo.Tramo_Mora
        SET dias_desde = @dias_desde, dias_hasta = @dias_hasta,
            porcentaje = @porcentaje, activo = @activo
        WHERE id_tramo = @id_tramo;

        IF @@ROWCOUNT = 0
            THROW 50334, 'El tramo indicado no existe.', 1;

        SET @id_tramo_salida = @id_tramo;
    END
END;
GO
