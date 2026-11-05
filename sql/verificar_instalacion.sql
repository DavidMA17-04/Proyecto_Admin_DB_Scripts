/* ---------------------------------------------------------------------
   Diagnóstico de solo lectura — ASADA Santa Cruz (no modifica datos).
   Uso: sqlcmd -S localhost -E -C -f 65001 -i verificar_instalacion.sql
   --------------------------------------------------------------------- */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
GO

DECLARE @nivel varchar(12), @codigo varchar(80), @detalle nvarchar(500);

IF OBJECT_ID('tempdb..#diag') IS NOT NULL DROP TABLE #diag;
CREATE TABLE #diag (
    nivel   varchar(12)  NOT NULL,
    codigo  varchar(80)  NOT NULL,
    detalle nvarchar(500) NOT NULL
);

-- Bases
IF DB_ID('ASADA') IS NULL
    INSERT INTO #diag VALUES ('Error', 'DB_ASADA', 'La base ASADA no existe.');
ELSE IF CONVERT(varchar(128), DATABASEPROPERTYEX('ASADA', 'Status')) <> 'ONLINE'
    INSERT INTO #diag VALUES ('Error', 'DB_ASADA', CONCAT('ASADA no está ONLINE: ', CONVERT(varchar(128), DATABASEPROPERTYEX('ASADA', 'Status'))));
ELSE
    INSERT INTO #diag VALUES ('OK', 'DB_ASADA', 'ASADA existe y está ONLINE.');

IF DB_ID('ASADA_DW') IS NULL
    INSERT INTO #diag VALUES ('Error', 'DB_ASADA_DW', 'La base ASADA_DW no existe.');
ELSE IF CONVERT(varchar(128), DATABASEPROPERTYEX('ASADA_DW', 'Status')) <> 'ONLINE'
    INSERT INTO #diag VALUES ('Error', 'DB_ASADA_DW', CONCAT('ASADA_DW no está ONLINE: ', CONVERT(varchar(128), DATABASEPROPERTYEX('ASADA_DW', 'Status'))));
ELSE
    INSERT INTO #diag VALUES ('OK', 'DB_ASADA_DW', 'ASADA_DW existe y está ONLINE.');

IF DB_ID('ASADA') IS NOT NULL
BEGIN
    IF OBJECT_ID('ASADA.dbo.Abonado_Fisico', 'U') IS NULL
        INSERT INTO #diag VALUES ('Error', 'TAB_ABONADO_FISICO', 'Falta tabla Abonado_Fisico en ASADA.');
    ELSE
        INSERT INTO #diag VALUES ('OK', 'TAB_ABONADO_FISICO', 'Tabla Abonado_Fisico presente.');

    IF OBJECT_ID('ASADA.dbo.Abonado_Juridico', 'U') IS NULL
        INSERT INTO #diag VALUES ('Error', 'TAB_ABONADO_JURIDICO', 'Falta tabla Abonado_Juridico en ASADA.');
    ELSE
        INSERT INTO #diag VALUES ('OK', 'TAB_ABONADO_JURIDICO', 'Tabla Abonado_Juridico presente.');

    IF OBJECT_ID('ASADA.dbo.Conexion', 'U') IS NULL
        INSERT INTO #diag VALUES ('Error', 'TAB_CONEXION', 'Falta tabla Conexion en ASADA.');
    ELSE
        INSERT INTO #diag VALUES ('OK', 'TAB_CONEXION', 'Tabla Conexion presente.');

    IF OBJECT_ID('ASADA.dbo.Medidor', 'U') IS NULL
        INSERT INTO #diag VALUES ('Error', 'TAB_MEDIDOR', 'Falta tabla Medidor en ASADA.');
    ELSE
        INSERT INTO #diag VALUES ('OK', 'TAB_MEDIDOR', 'Tabla Medidor presente.');

    IF OBJECT_ID('ASADA.dbo.Politica_Respaldo', 'U') IS NULL
        INSERT INTO #diag VALUES ('Error', 'TAB_POLITICA', 'Falta Politica_Respaldo.');
    ELSE
    BEGIN
        IF COL_LENGTH('ASADA.dbo.Politica_Respaldo', 'nombre_base') IS NOT NULL
        BEGIN
            INSERT INTO #diag
            SELECT 'OK', CONCAT('POL_', p.nombre_base, '_', t.nombre_respaldo),
                   CONCAT('Política activa id=', p.id_politica, ' ruta=', p.ruta_destino)
            FROM ASADA.dbo.Politica_Respaldo p
            JOIN ASADA.dbo.Tipo_Respaldo t ON t.id_tipo_respaldo = p.id_tipo_respaldo
            WHERE p.activo = 1;
        END
    END

    DECLARE @m_col bit = 0, @m_ck bit = 0, @m_pdw bit = 0, @m_sp bit = 0, @m_param bit = 0, @m_ok int;
    IF OBJECT_ID('ASADA.dbo.Politica_Respaldo', 'U') IS NOT NULL
       AND COL_LENGTH('ASADA.dbo.Politica_Respaldo', 'nombre_base') IS NOT NULL
        SET @m_col = 1;
    IF EXISTS (
        SELECT 1 FROM ASADA.sys.check_constraints
        WHERE name = N'CK_PoliticaRespaldo_Base'
          AND parent_object_id = OBJECT_ID(N'ASADA.dbo.Politica_Respaldo'))
        SET @m_ck = 1;
    IF @m_col = 1 AND EXISTS (SELECT 1 FROM ASADA.dbo.Politica_Respaldo WHERE nombre_base = N'ASADA_DW')
        SET @m_pdw = 1;
    IF OBJECT_ID('ASADA.dbo.sp_EjecutarRespaldo', 'P') IS NOT NULL
        SET @m_sp = 1;
    IF EXISTS (
        SELECT 1 FROM ASADA.sys.parameters p
        INNER JOIN ASADA.sys.procedures pr ON p.object_id = pr.object_id
        WHERE pr.object_id = OBJECT_ID(N'ASADA.dbo.sp_GestionarPoliticaRespaldo')
          AND p.name = N'@nombre_base')
        SET @m_param = 1;

    SET @m_ok = CAST(@m_col AS int) + CAST(@m_ck AS int) + CAST(@m_pdw AS int) + CAST(@m_sp AS int) + CAST(@m_param AS int);

    IF @m_ok = 5
        INSERT INTO #diag VALUES ('OK', 'MIG_RESP_MULTIBASE',
            'Migración respaldos_multibase aplicada (5/5 marcadores de metadatos).');
    ELSE IF @m_ok = 0
        INSERT INTO #diag VALUES ('Advertencia', 'MIG_RESP_MULTIBASE',
            'Migración respaldos_multibase pendiente (0/5 marcadores).');
    ELSE
        INSERT INTO #diag VALUES ('Advertencia', 'MIG_RESP_PARCIAL',
            CONCAT('Migración respaldos_multibase parcial (', @m_ok, '/5): col=', @m_col,
                   ' ck=', @m_ck, ' polDW=', @m_pdw, ' spEjecutar=', @m_sp, ' spGestionarParam=', @m_param, '.'));

    IF OBJECT_ID('ASADA.dbo.sp_EjecutarRespaldo', 'P') IS NULL
        INSERT INTO #diag VALUES ('Error', 'SP_RESPALDO', 'Falta sp_EjecutarRespaldo.');
    ELSE
    BEGIN
        DECLARE @def_sp nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'ASADA.dbo.sp_EjecutarRespaldo'));
        IF @def_sp IS NULL
            INSERT INTO #diag VALUES ('Advertencia', 'SP_RESPALDO_DEF',
                'sp_EjecutarRespaldo existe; la definición no es visible (sin VIEW DEFINITION). No se infiere multibase desde texto.');
        ELSE IF @def_sp NOT LIKE N'%nombre_base%' AND @def_sp NOT LIKE N'%@base%'
            INSERT INTO #diag VALUES ('Advertencia', 'SP_RESPALDO_BODY',
                'Definición accesible de sp_EjecutarRespaldo sin indicios multibase; contraste con marcadores MIG_RESP_*.');
        ELSE
            INSERT INTO #diag VALUES ('OK', 'SP_RESPALDO_DEF',
                'Definición accesible de sp_EjecutarRespaldo coherente con respaldo multibase.');
    END

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

IF @err > 0
    RAISERROR(N'Diagnóstico ASADA: hay errores críticos (nivel Error).', 16, 1);
GO

IF DB_ID('ASADA') IS NOT NULL
BEGIN
    PRINT '--- sp_ValidarCargaDW (solo lectura de reglas) ---';
    EXEC ASADA.dbo.sp_ValidarCargaDW;
END
GO
