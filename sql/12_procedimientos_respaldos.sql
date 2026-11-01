SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Script 12: Procedimientos - Respaldos y recuperación Point-in-Time 
   --------------------------------------------------------------------- */

USE ASADA;
GO

   --Políticas
-- Registra o modifica una política. Si se cambian frecuencia u hora, hay que
-- ajustar también la programación del job correspondiente.
CREATE OR ALTER PROCEDURE dbo.sp_GestionarPoliticaRespaldo
    @id_tipo_respaldo  int,
    @nombre_politica   varchar(100),
    @frecuencia        varchar(50),
    @hora_ejecucion    time(0),
    @retencion_dias    int,
    @ruta_destino      varchar(300),
    @activo            bit = 1,
    @id_politica       int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Tipo_Respaldo WHERE id_tipo_respaldo = @id_tipo_respaldo)
        THROW 50801, 'El tipo de respaldo indicado no existe.', 1;

    IF @retencion_dias <= 0
        THROW 50802, 'Los días de retención deben ser mayores que cero.', 1;

    IF NULLIF(LTRIM(@ruta_destino), '') IS NULL
        THROW 50803, 'Debe indicar la ruta de destino.', 1;

    -- La ruta siempre termina en separador para poder concatenar el nombre del archivo.
    IF RIGHT(@ruta_destino, 1) NOT IN ('\', '/')
        SET @ruta_destino += CASE WHEN CHARINDEX('/', @ruta_destino) > 0 THEN '/' ELSE '\' END;

    IF @id_politica IS NULL
    BEGIN
        INSERT INTO dbo.Politica_Respaldo (id_tipo_respaldo, nombre_politica, frecuencia, hora_ejecucion, retencion_dias, ruta_destino, activo)
        VALUES (@id_tipo_respaldo, @nombre_politica, @frecuencia, @hora_ejecucion, @retencion_dias, @ruta_destino, @activo);
        SET @id_politica = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE dbo.Politica_Respaldo
        SET id_tipo_respaldo = @id_tipo_respaldo, nombre_politica = @nombre_politica, frecuencia = @frecuencia,
            hora_ejecucion = @hora_ejecucion, retencion_dias = @retencion_dias, ruta_destino = @ruta_destino, activo = @activo
        WHERE id_politica = @id_politica;

        IF @@ROWCOUNT = 0 THROW 50804, 'La política indicada no existe.', 1;
    END
END;
GO

   --Registro de resultados
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarResultadoRespaldo
    @id_politica    int,
    @fecha_inicio   datetime,
    @fecha_fin      datetime,
    @ruta_archivo   varchar(300),
    @tamano_bytes   bigint       = NULL,
    @estado         varchar(20),
    @mensaje_error  varchar(500) = NULL,
    @id_respaldo    int          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Historial_Respaldo (id_politica, fecha_inicio, fecha_fin, ruta_archivo, tamano_bytes, estado, mensaje_error)
    VALUES (@id_politica, @fecha_inicio, @fecha_fin, @ruta_archivo, @tamano_bytes, @estado, @mensaje_error);

    SET @id_respaldo = SCOPE_IDENTITY();
END;
GO

-- Si @id_restauracion es NULL registra una restauración nueva; si no, actualiza su resultado.
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarResultadoRestauracion
    @punto_recuperacion  datetime     = NULL,
    @base_destino        varchar(100) = NULL,
    @motivo              varchar(250) = NULL,
    @estado              varchar(20),
    @fecha_inicio        datetime     = NULL,
    @fecha_fin           datetime     = NULL,
    @observacion         varchar(500) = NULL,
    @id_usuario_sistema  int          = NULL,
    @id_restauracion     int          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @id_restauracion IS NULL
    BEGIN
        INSERT INTO dbo.Historial_Restauracion
            (id_usuario_sistema, punto_recuperacion, fecha_inicio, fecha_fin, estado, base_destino, motivo, observacion)
        VALUES
            (COALESCE(@id_usuario_sistema, dbo.fn_UsuarioActual()), @punto_recuperacion, @fecha_inicio, @fecha_fin,
             @estado, @base_destino, @motivo, @observacion);
        SET @id_restauracion = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE dbo.Historial_Restauracion
        SET estado       = @estado,
            fecha_inicio = ISNULL(@fecha_inicio, fecha_inicio),
            fecha_fin    = ISNULL(@fecha_fin, fecha_fin),
            observacion  = ISNULL(@observacion, observacion)
        WHERE id_restauracion = @id_restauracion;
END;
GO

   --Ejecución y verificación
-- Ejecuta el respaldo de una política (completo, diferencial o log) y lo registra.
-- Lo invocan los jobs Job_RespaldoCompleto, Job_RespaldoDiferencial y Job_RespaldoLogTransacciones.
CREATE OR ALTER PROCEDURE dbo.sp_EjecutarRespaldo
    @id_politica  int,
    @verificar    bit = 1,
    @id_respaldo  int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @tipo varchar(15), @ruta varchar(300), @activo bit,
            @archivo nvarchar(400), @sql nvarchar(max), @inicio datetime = GETDATE(),
            @tamano bigint, @mensaje varchar(500), @base sysname = DB_NAME(), @fin datetime;

    SELECT @tipo = t.nombre_respaldo, @ruta = p.ruta_destino, @activo = p.activo
    FROM dbo.Politica_Respaldo p
    JOIN dbo.Tipo_Respaldo t ON t.id_tipo_respaldo = p.id_tipo_respaldo
    WHERE p.id_politica = @id_politica;

    IF @tipo IS NULL
        THROW 50804, 'La política indicada no existe.', 1;

    IF @activo = 0
        THROW 50805, 'La política está desactivada.', 1;

    SET @archivo = CONCAT(@ruta, @base, '_', @tipo, '_', FORMAT(@inicio, 'yyyyMMdd_HHmmss'),
                          CASE @tipo WHEN 'Log' THEN '.trn' ELSE '.bak' END);

    SET @sql = CASE @tipo
        WHEN 'Completo'    THEN N'BACKUP DATABASE ' + QUOTENAME(@base) + N' TO DISK = @archivo WITH CHECKSUM, INIT, NAME = @nombre;'
        WHEN 'Diferencial' THEN N'BACKUP DATABASE ' + QUOTENAME(@base) + N' TO DISK = @archivo WITH DIFFERENTIAL, CHECKSUM, INIT, NAME = @nombre;'
        WHEN 'Log'         THEN N'BACKUP LOG '      + QUOTENAME(@base) + N' TO DISK = @archivo WITH CHECKSUM, INIT, NAME = @nombre;'
    END;

    BEGIN TRY
        DECLARE @nombre nvarchar(128) = CONCAT(@base, ' - ', @tipo, ' - ', FORMAT(@inicio, 'yyyy-MM-dd HH:mm:ss'));
        EXEC sys.sp_executesql @sql, N'@archivo nvarchar(400), @nombre nvarchar(128)', @archivo = @archivo, @nombre = @nombre;
        SET @fin = GETDATE();

        -- El tamaño se toma del historial de msdb (si el usuario tiene acceso).
        BEGIN TRY
            SELECT TOP (1) @tamano = bs.backup_size
            FROM msdb.dbo.backupset bs
            JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = bs.media_set_id
            WHERE mf.physical_device_name = @archivo
            ORDER BY bs.backup_set_id DESC;
        END TRY
        BEGIN CATCH
            SET @tamano = NULL;
        END CATCH

        EXEC dbo.sp_RegistrarResultadoRespaldo
            @id_politica = @id_politica, @fecha_inicio = @inicio, @fecha_fin = @fin,
            @ruta_archivo = @archivo, @tamano_bytes = @tamano, @estado = 'Exitoso',
            @id_respaldo = @id_respaldo OUTPUT;
    END TRY
    BEGIN CATCH
        SET @mensaje = LEFT(ERROR_MESSAGE(), 500);
        SET @fin = GETDATE();

        EXEC dbo.sp_RegistrarResultadoRespaldo
            @id_politica = @id_politica, @fecha_inicio = @inicio, @fecha_fin = @fin,
            @ruta_archivo = @archivo, @estado = 'Fallido', @mensaje_error = @mensaje,
            @id_respaldo = @id_respaldo OUTPUT;

        -- Se relanza el error para que el job quede marcado como fallido.
        THROW;
    END CATCH

    IF @verificar = 1
        EXEC dbo.sp_VerificarIntegridadRespaldos @id_respaldo = @id_respaldo;
END;
GO

-- Valida los archivos con RESTORE VERIFYONLY. Sin parámetro revisa todos los
-- respaldos exitosos que aún no han sido verificados.
CREATE OR ALTER PROCEDURE dbo.sp_VerificarIntegridadRespaldos
    @id_respaldo int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id int, @ruta nvarchar(300), @sql nvarchar(max);
    DECLARE @resultado TABLE (id_respaldo int, ruta_archivo nvarchar(300), resultado varchar(10), mensaje nvarchar(4000));

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT id_respaldo, ruta_archivo
        FROM dbo.Historial_Respaldo
        WHERE estado = 'Exitoso'
          AND ((@id_respaldo IS NULL AND verificado = 0) OR id_respaldo = @id_respaldo);

    OPEN cur;
    FETCH NEXT FROM cur INTO @id, @ruta;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SET @sql = N'RESTORE VERIFYONLY FROM DISK = @ruta WITH CHECKSUM;';
            EXEC sys.sp_executesql @sql, N'@ruta nvarchar(300)', @ruta = @ruta;

            UPDATE dbo.Historial_Respaldo SET verificado = 1 WHERE id_respaldo = @id;
            INSERT INTO @resultado VALUES (@id, @ruta, 'Válido', NULL);
        END TRY
        BEGIN CATCH
            INSERT INTO @resultado VALUES (@id, @ruta, 'Inválido', ERROR_MESSAGE());

            DECLARE @desc varchar(max) = CONCAT('El respaldo ', @id, ' (', @ruta, ') no pasó la verificación: ', ERROR_MESSAGE());
            EXEC dbo.sp_RegistrarEventoBitacora 'ALERTA', 'Historial_Respaldo', @desc;
        END CATCH

        FETCH NEXT FROM cur INTO @id, @ruta;
    END
    CLOSE cur;
    DEALLOCATE cur;

    SELECT * FROM @resultado;
END;
GO

   --Restauración a un punto en el tiempo (STOPAT)
CREATE OR ALTER PROCEDURE dbo.sp_RestaurarPuntoEnTiempo
    @punto_recuperacion   datetime,
    @motivo               varchar(250),
    @base_destino         sysname = NULL,
    @solo_generar_script  bit     = 0,
    @id_restauracion      int     = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @base sysname = DB_NAME(),
            @full_ruta nvarchar(300), @full_ckpt numeric(25,0), @full_last numeric(25,0),
            @diff_ruta nvarchar(300), @diff_last numeric(25,0),
            @base_last numeric(25,0), @sql nvarchar(max) = N'', @move nvarchar(max) = N'',
            @ruta_datos nvarchar(400), @ruta_log nvarchar(400), @inicio datetime,
            @stopat varchar(30), @mensaje varchar(500), @n int, @fin datetime;

    SET @base_destino = ISNULL(@base_destino, @base + '_Restaurada');

    IF NULLIF(LTRIM(@motivo), '') IS NULL
        THROW 50806, 'Debe indicar el motivo de la restauración.', 1;

    IF @punto_recuperacion >= GETDATE()
        THROW 50807, 'El punto de recuperación debe ser una fecha pasada.', 1;

    IF @base_destino = @base AND @solo_generar_script = 0
        THROW 50808, 'No se puede restaurar sobre la base en uso desde ella misma. Restaure en otra base o genere el script (@solo_generar_script = 1) y ejecútelo desde master.', 1;

    -- Respaldos exitosos de esta base con su información de LSN en msdb.
    SELECT h.id_respaldo, h.ruta_archivo, bs.type, bs.first_lsn, bs.last_lsn, bs.checkpoint_lsn,
           bs.differential_base_lsn, bs.backup_finish_date
    INTO #respaldos
    FROM dbo.Historial_Respaldo h
    JOIN msdb.dbo.backupmediafamily mf ON mf.physical_device_name = h.ruta_archivo
    JOIN msdb.dbo.backupset bs         ON bs.media_set_id = mf.media_set_id
    WHERE h.estado = 'Exitoso' AND bs.database_name = @base;

    -- 1) Último respaldo completo terminado antes del punto.
    SELECT TOP (1) @full_ruta = ruta_archivo, @full_ckpt = checkpoint_lsn, @full_last = last_lsn
    FROM #respaldos
    WHERE type = 'D' AND backup_finish_date <= @punto_recuperacion
    ORDER BY backup_finish_date DESC;

    IF @full_ruta IS NULL
        THROW 50809, 'No existe un respaldo completo exitoso anterior al punto de recuperación.', 1;

    -- 2) Último diferencial basado en ese completo y terminado antes del punto.
    SELECT TOP (1) @diff_ruta = ruta_archivo, @diff_last = last_lsn
    FROM #respaldos
    WHERE type = 'I' AND differential_base_lsn = @full_ckpt AND backup_finish_date <= @punto_recuperacion
    ORDER BY backup_finish_date DESC;

    SET @base_last = COALESCE(@diff_last, @full_last);

    -- 3) Logs posteriores, en orden, hasta el primero que cubre el punto.
    SELECT ROW_NUMBER() OVER (ORDER BY first_lsn) AS orden, ruta_archivo, first_lsn, last_lsn, backup_finish_date
    INTO #logs
    FROM #respaldos
    WHERE type = 'L' AND last_lsn > @base_last;

    SELECT @n = MIN(orden) FROM #logs WHERE backup_finish_date >= @punto_recuperacion;

    IF @n IS NULL
        THROW 50810, 'No hay respaldos de log que cubran el punto de recuperación. Ejecute un respaldo de log e intente de nuevo.', 1;

    DELETE FROM #logs WHERE orden > @n;

    -- La cadena de logs debe ser continua (sin huecos de LSN).
    IF (SELECT first_lsn FROM #logs WHERE orden = 1) > @base_last
       OR EXISTS (SELECT 1 FROM #logs a JOIN #logs b ON b.orden = a.orden + 1 WHERE b.first_lsn > a.last_lsn)
        THROW 50811, 'La cadena de respaldos de log está incompleta; no se puede restaurar a ese punto.', 1;

    -- Archivos físicos de la base restaurada en las rutas por defecto de la instancia.
    SET @ruta_datos = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(400));
    SET @ruta_log   = CAST(SERVERPROPERTY('InstanceDefaultLogPath')  AS nvarchar(400));

    SELECT @move += CONCAT(N', MOVE N''', name, N''' TO N''',
                           CASE WHEN type_desc = 'LOG' THEN @ruta_log ELSE @ruta_datos END,
                           @base_destino, N'_', name, CASE WHEN type_desc = 'LOG' THEN N'.ldf' ELSE N'.mdf' END, N'''')
    FROM sys.database_files;

    SET @stopat = CONVERT(varchar(30), @punto_recuperacion, 126);

    SET @sql = CONCAT(N'RESTORE DATABASE ', QUOTENAME(@base_destino), N' FROM DISK = N''', @full_ruta, N''' WITH NORECOVERY, REPLACE', @move, N';', CHAR(13), CHAR(10));

    IF @diff_ruta IS NOT NULL
        SET @sql += CONCAT(N'RESTORE DATABASE ', QUOTENAME(@base_destino), N' FROM DISK = N''', @diff_ruta, N''' WITH NORECOVERY;', CHAR(13), CHAR(10));

    SELECT @sql += CONCAT(N'RESTORE LOG ', QUOTENAME(@base_destino), N' FROM DISK = N''', ruta_archivo, N''' WITH ',
                          CASE WHEN orden = @n THEN CONCAT(N'STOPAT = ''', @stopat, N''', RECOVERY') ELSE N'NORECOVERY' END,
                          N';', CHAR(13), CHAR(10))
    FROM #logs
    ORDER BY orden;

    IF @solo_generar_script = 1
    BEGIN
        SELECT @sql AS script_restauracion;
        RETURN;
    END

    SET @inicio = GETDATE();
    EXEC dbo.sp_RegistrarResultadoRestauracion
        @punto_recuperacion = @punto_recuperacion, @base_destino = @base_destino, @motivo = @motivo,
        @estado = 'En proceso', @fecha_inicio = @inicio, @id_restauracion = @id_restauracion OUTPUT;

    BEGIN TRY
        EXEC sys.sp_executesql @sql;
        SET @fin = GETDATE();

        DECLARE @obs varchar(500) = CONCAT('Cadena aplicada: completo', IIF(@diff_ruta IS NULL, '', ' + diferencial'), ' + ', @n, ' log(s).');
        EXEC dbo.sp_RegistrarResultadoRestauracion
            @id_restauracion = @id_restauracion, @estado = 'Exitosa', @fecha_fin = @fin, @observacion = @obs;

        DECLARE @desc varchar(max) = CONCAT('Restauración al ', @stopat, ' en la base ', @base_destino, '. Motivo: ', @motivo);
        EXEC dbo.sp_RegistrarEventoBitacora 'RESTORE', 'Historial_Restauracion', @desc;
    END TRY
    BEGIN CATCH
        SET @mensaje = LEFT(ERROR_MESSAGE(), 500);
        SET @fin = GETDATE();
        EXEC dbo.sp_RegistrarResultadoRestauracion
            @id_restauracion = @id_restauracion, @estado = 'Fallida', @fecha_fin = @fin, @observacion = @mensaje;

        DECLARE @desc_error varchar(max) = CONCAT('Falló la restauración al ', @stopat, ': ', @mensaje);
        EXEC dbo.sp_RegistrarEventoBitacora 'ALERTA', 'Historial_Restauracion', @desc_error;
        THROW;
    END CATCH
END;
GO

   --Consultas
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarHistorialRespaldos
    @id_politica  int         = NULL,
    @desde        datetime    = NULL,
    @hasta        datetime    = NULL,
    @estado       varchar(20) = NULL,
    @verificado   bit         = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT h.id_respaldo, p.nombre_politica, t.nombre_respaldo AS tipo,
           h.fecha_inicio, h.fecha_fin, dbo.fn_CalcularDuracionRespaldo(h.id_respaldo) AS duracion_segundos,
           h.ruta_archivo, h.tamano_bytes, h.estado, h.verificado, h.mensaje_error,
           dbo.fn_CalcularFechaRetencionRespaldo(h.id_respaldo) AS conservar_hasta
    FROM dbo.Historial_Respaldo h
    JOIN dbo.Politica_Respaldo p ON p.id_politica = h.id_politica
    JOIN dbo.Tipo_Respaldo     t ON t.id_tipo_respaldo = p.id_tipo_respaldo
    WHERE (@id_politica IS NULL OR h.id_politica = @id_politica)
      AND (@desde       IS NULL OR h.fecha_inicio >= @desde)
      AND (@hasta       IS NULL OR h.fecha_inicio <= @hasta)
      AND (@estado      IS NULL OR h.estado = @estado)
      AND (@verificado  IS NULL OR h.verificado = @verificado)
    ORDER BY h.fecha_inicio DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarHistorialRestauracion
    @desde   datetime    = NULL,
    @hasta   datetime    = NULL,
    @estado  varchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.id_restauracion, r.fecha_solicitud, ISNULL(u.nombre_usuario, 'SISTEMA') AS solicitante,
           r.punto_recuperacion, r.base_destino, r.fecha_inicio, r.fecha_fin, r.estado, r.motivo, r.observacion
    FROM dbo.Historial_Restauracion r
    LEFT JOIN dbo.Usuario_Sistema u ON u.id_usuario_sistema = r.id_usuario_sistema
    WHERE (@desde  IS NULL OR r.fecha_solicitud >= @desde)
      AND (@hasta  IS NULL OR r.fecha_solicitud <= @hasta)
      AND (@estado IS NULL OR r.estado = @estado)
    ORDER BY r.fecha_solicitud DESC;
END;
GO
