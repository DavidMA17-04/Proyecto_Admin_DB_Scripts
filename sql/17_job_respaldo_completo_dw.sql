/* Instala únicamente Job_RespaldoCompletoDW (deshabilitado). No recrea los demás jobs. */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE msdb;
GO

IF OBJECT_ID('dbo.sp_ASADA_CrearJob', 'P') IS NULL
    THROW 51021, 'Ejecute primero la sección sp_ASADA_CrearJob de 17_jobs_sql_agent.sql.', 1;
GO

EXEC dbo.sp_ASADA_CrearJob
    @nombre = N'Job_RespaldoCompletoDW',
    @descripcion = N'ASADA_DW - Respaldo completo diario del Data Warehouse (post-ETL).',
    @comando = N'DECLARE @p int = (SELECT TOP (1) p.id_politica FROM dbo.Politica_Respaldo p
                 JOIN dbo.Tipo_Respaldo t ON t.id_tipo_respaldo = p.id_tipo_respaldo
                 WHERE t.nombre_respaldo = ''Completo'' AND p.nombre_base = ''ASADA_DW'' AND p.activo = 1 ORDER BY p.id_politica);
                 EXEC dbo.sp_EjecutarRespaldo @id_politica = @p;',
    @freq_type = 4, @freq_interval = 1, @hora_inicio = 023000,
    @enabled = 0;
GO

SELECT j.name, j.enabled, s.enabled AS schedule_enabled, s.active_start_time
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
WHERE j.name = N'Job_RespaldoCompletoDW';
GO
