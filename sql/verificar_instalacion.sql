/* ---------------------------------------------------------------------
   Diagnóstico de solo lectura — ASADA Santa Cruz (no modifica datos).
   Uso: sqlcmd -S localhost -E -C -f 65001 -i verificar_instalacion.sql
   --------------------------------------------------------------------- */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
GO

DECLARE @nivel varchar(10), @codigo varchar(40), @detalle nvarchar(400);

IF OBJECT_ID('tempdb..#diag') IS NOT NULL DROP TABLE #diag;
CREATE TABLE #diag (
    nivel   varchar(10)  NOT NULL,
    codigo  varchar(40)  NOT NULL,
    detalle nvarchar(400) NOT NULL
);

-- Bases
IF DB_ID('ASADA') IS NULL
    INSERT INTO #diag VALUES ('Error', 'DB_ASADA', 'La base ASADA no existe.');
ELSE IF DATABASEPROPERTYEX('ASADA', 'Status') <> 'ONLINE'
    INSERT INTO #diag VALUES ('Error', 'DB_ASADA', CONCAT('ASADA no está ONLINE: ', DATABASEPROPERTYEX('ASADA', 'Status')));
ELSE
    INSERT INTO #diag VALUES ('OK', 'DB_ASADA', 'ASADA existe y está ONLINE.');

IF DB_ID('ASADA_DW') IS NULL
    INSERT INTO #diag VALUES ('Error', 'DB_ASADA_DW', 'La base ASADA_DW no existe.');
ELSE IF DATABASEPROPERTYEX('ASADA_DW', 'Status') <> 'ONLINE'
    INSERT INTO #diag VALUES ('Error', 'DB_ASADA_DW', CONCAT('ASADA_DW no está ONLINE: ', DATABASEPROPERTYEX('ASADA_DW', 'Status')));
ELSE
    INSERT INTO #diag VALUES ('OK', 'DB_ASADA_DW', 'ASADA_DW existe y está ONLINE.');

IF DB_ID('ASADA') IS NOT NULL
BEGIN
    IF OBJECT_ID('ASADA.dbo.Abonado', 'U') IS NULL
        INSERT INTO #diag VALUES ('Error', 'TAB_ABONADO', 'Falta tabla Abonado en ASADA.');
    ELSE
        INSERT INTO #diag VALUES ('OK', 'TAB_ABONADO', 'Tabla Abonado presente.');

    IF OBJECT_ID('ASADA.dbo.Politica_Respaldo', 'U') IS NULL
        INSERT INTO #diag VALUES ('Error', 'TAB_POLITICA', 'Falta Politica_Respaldo.');
    ELSE
    BEGIN
        IF COL_LENGTH('ASADA.dbo.Politica_Respaldo', 'nombre_base') IS NULL
            INSERT INTO #diag VALUES ('Advertencia', 'MIG_RESP_DW', 'Falta columna nombre_base (migración 22 pendiente).');
        ELSE
            INSERT INTO #diag VALUES ('OK', 'MIG_RESP_DW', 'Políticas multibase (nombre_base) presentes.');

        INSERT INTO #diag
        SELECT 'OK', CONCAT('POL_', p.nombre_base, '_', t.nombre_respaldo),
               CONCAT('Política activa id=', p.id_politica, ' ruta=', p.ruta_destino)
        FROM ASADA.dbo.Politica_Respaldo p
        JOIN ASADA.dbo.Tipo_Respaldo t ON t.id_tipo_respaldo = p.id_tipo_respaldo
        WHERE p.activo = 1;

        IF NOT EXISTS (SELECT 1 FROM ASADA.dbo.Politica_Respaldo WHERE nombre_base = 'ASADA_DW')
            INSERT INTO #diag VALUES ('Advertencia', 'POL_DW', 'No hay política de respaldo para ASADA_DW.');
    END

    IF OBJECT_ID('ASADA.dbo.sp_EjecutarRespaldo', 'P') IS NULL
        INSERT INTO #diag VALUES ('Error', 'SP_RESPALDO', 'Falta sp_EjecutarRespaldo.');
    ELSE IF OBJECT_DEFINITION(OBJECT_ID('ASADA.dbo.sp_EjecutarRespaldo')) NOT LIKE '%nombre_base%'
        INSERT INTO #diag VALUES ('Advertencia', 'SP_RESPALDO', 'sp_EjecutarRespaldo parece versión anterior (sin nombre_base).');
    ELSE
        INSERT INTO #diag VALUES ('OK', 'SP_RESPALDO', 'sp_EjecutarRespaldo multibase.');

    IF OBJECT_ID('ASADA.dbo.sp_EjecutarCargaDW', 'P') IS NULL
        INSERT INTO #diag VALUES ('Error', 'SP_ETL', 'Falta sp_EjecutarCargaDW.');
    ELSE
        INSERT INTO #diag VALUES ('OK', 'SP_ETL', 'sp_EjecutarCargaDW presente.');

    IF EXISTS (SELECT 1 FROM ASADA.dbo.Medidor WHERE numero_serie LIKE 'SC-%')
        INSERT INTO #diag VALUES ('OK', 'DEMO', 'Datos demo detectados (medidores SC-).');
    ELSE
        INSERT INTO #diag VALUES ('Advertencia', 'DEMO', 'No hay medidores SC- (demo no cargada).');

    IF OBJECT_ID('ASADA.dbo.Tramo_Mora', 'U') IS NULL
        INSERT INTO #diag VALUES ('Advertencia', 'MIG_DEV', 'Falta Tramo_Mora (actualizar_a_development pendiente).');
    ELSE
        INSERT INTO #diag VALUES ('OK', 'MIG_DEV', 'Tramo_Mora presente.');
END

IF DB_ID('ASADA_DW') IS NOT NULL
BEGIN
    IF OBJECT_ID('ASADA_DW.dbo.FACT_CONSUMO', 'U') IS NULL
        INSERT INTO #diag VALUES ('Error', 'FACT_DW', 'Falta FACT_CONSUMO en ASADA_DW.');
    ELSE
    BEGIN
        DECLARE @fc bigint, @ff bigint, @fp bigint, @fm int, @fmn int, @fi int;
        SELECT @fc = COUNT(*) FROM ASADA_DW.dbo.FACT_CONSUMO;
        SELECT @ff = COUNT(*) FROM ASADA_DW.dbo.FACT_FACTURACION;
        SELECT @fp = COUNT(*) FROM ASADA_DW.dbo.FACT_PAGO;
        SELECT @fm = COUNT(*) FROM ASADA_DW.dbo.FACT_MOROSIDAD;
        SELECT @fmn = COUNT(*) FROM ASADA_DW.dbo.FACT_MANTENIMIENTO;
        SELECT @fi = COUNT(*) FROM ASADA_DW.dbo.FACT_INCIDENCIA;
        INSERT INTO #diag VALUES ('OK', 'FACT_COUNTS',
            CONCAT('CONSUMO=', @fc, ' FACT=', @ff, ' PAGO=', @fp, ' MORA=', @fm, ' MANT=', @fmn, ' INC=', @fi));

        IF @fc = 0 AND EXISTS (SELECT 1 FROM ASADA.dbo.Medidor WHERE numero_serie LIKE 'SC-%')
            INSERT INTO #diag VALUES ('Advertencia', 'FACT_VACIO', 'Demo en ASADA pero hechos DW en cero (ejecutar ETL).');
    END
END

-- Jobs (msdb)
IF DB_ID('ASADA') IS NOT NULL
BEGIN
    DECLARE @jobs TABLE (nombre sysname PRIMARY KEY, existe bit, enabled bit NULL);
    INSERT INTO @jobs (nombre, existe) VALUES
        (N'Job_RespaldoCompleto', 0), (N'Job_RespaldoDiferencial', 0), (N'Job_RespaldoLogTransacciones', 0),
        (N'Job_CargaNocturnaDW', 0), (N'Job_MantenimientoNocturno', 0), (N'Job_RespaldoCompletoDW', 0);

    UPDATE j SET existe = 1, enabled = sj.enabled
    FROM @jobs j
    JOIN msdb.dbo.sysjobs sj ON sj.name = j.nombre;

    INSERT INTO #diag
    SELECT CASE WHEN existe = 0 THEN 'Advertencia' WHEN enabled = 1 THEN 'Advertencia' ELSE 'OK' END,
           CONCAT('JOB_', nombre),
           CASE WHEN existe = 0 THEN 'Job no instalado.'
                WHEN enabled = 1 THEN 'Job instalado pero HABILITADO (revisar).'
                ELSE 'Job instalado y deshabilitado.' END
    FROM @jobs;
END

SELECT nivel, codigo, detalle FROM #diag ORDER BY
    CASE nivel WHEN 'Error' THEN 1 WHEN 'Advertencia' THEN 2 ELSE 3 END, codigo;

DECLARE @err int = (SELECT COUNT(*) FROM #diag WHERE nivel = 'Error');
DECLARE @adv int = (SELECT COUNT(*) FROM #diag WHERE nivel = 'Advertencia');
PRINT CONCAT('Resumen diagnóstico: ', @err, ' error(es), ', @adv, ' advertencia(s).');
GO

IF DB_ID('ASADA') IS NOT NULL
BEGIN
    PRINT '--- sp_ValidarCargaDW (solo lectura de reglas) ---';
    EXEC ASADA.dbo.sp_ValidarCargaDW;
END
GO
