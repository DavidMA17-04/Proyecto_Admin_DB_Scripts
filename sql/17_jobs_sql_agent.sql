SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Script 17: Tareas programadas 
   --------------------------------------------------------------------- */
USE msdb;
GO

-- Crea (o recrea) un job con un paso T-SQL sobre la base ASADA.
CREATE OR ALTER PROCEDURE dbo.sp_ASADA_CrearJob
    @nombre                 sysname,
    @descripcion            nvarchar(512),
    @comando                nvarchar(max),
    @freq_type              int,          -- 4 = diario, 8 = semanal
    @freq_interval          int,          -- diario: 1 | semanal: suma de días (1 dom, 2 lun, 4 mar, 8 mié, 16 jue, 32 vie, 64 sáb)
    @hora_inicio            int,          -- HHMMSS
    @freq_subday_type       int = 1,      -- 1 = una vez, 4 = cada N minutos
    @freq_subday_interval   int = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @nombre)
        EXEC msdb.dbo.sp_delete_job @job_name = @nombre, @delete_unused_schedule = 1;

    EXEC msdb.dbo.sp_add_job @job_name = @nombre, @description = @descripcion, @enabled = 1;

    EXEC msdb.dbo.sp_add_jobstep
        @job_name = @nombre, @step_name = N'Ejecutar', @subsystem = N'TSQL',
        @database_name = N'ASADA', @command = @comando,
        @on_success_action = 1, @on_fail_action = 2;

    DECLARE @horario sysname = @nombre + N' - horario';
    EXEC msdb.dbo.sp_add_schedule
        @schedule_name = @horario, @enabled = 1,
        @freq_type = @freq_type, @freq_interval = @freq_interval,
        @freq_recurrence_factor = 1,
        @freq_subday_type = @freq_subday_type, @freq_subday_interval = @freq_subday_interval,
        @active_start_time = @hora_inicio;

    EXEC msdb.dbo.sp_attach_schedule @job_name = @nombre, @schedule_name = @horario;
    EXEC msdb.dbo.sp_add_jobserver   @job_name = @nombre, @server_name = N'(local)';
END;
GO

-- Respaldo completo: domingos a la 01:00
EXEC dbo.sp_ASADA_CrearJob
    @nombre = N'Job_RespaldoCompleto',
    @descripcion = N'ASADA - Respaldo completo semanal (R10).',
    @comando = N'DECLARE @p int = (SELECT TOP (1) p.id_politica FROM dbo.Politica_Respaldo p
                 JOIN dbo.Tipo_Respaldo t ON t.id_tipo_respaldo = p.id_tipo_respaldo
                 WHERE t.nombre_respaldo = ''Completo'' AND p.activo = 1 ORDER BY p.id_politica);
                 EXEC dbo.sp_EjecutarRespaldo @id_politica = @p;',
    @freq_type = 8, @freq_interval = 1, @hora_inicio = 010000;

-- Respaldo diferencial: lunes a sábado a la 01:00
EXEC dbo.sp_ASADA_CrearJob
    @nombre = N'Job_RespaldoDiferencial',
    @descripcion = N'ASADA - Respaldo diferencial diario sobre el último completo (R10).',
    @comando = N'DECLARE @p int = (SELECT TOP (1) p.id_politica FROM dbo.Politica_Respaldo p
                 JOIN dbo.Tipo_Respaldo t ON t.id_tipo_respaldo = p.id_tipo_respaldo
                 WHERE t.nombre_respaldo = ''Diferencial'' AND p.activo = 1 ORDER BY p.id_politica);
                 EXEC dbo.sp_EjecutarRespaldo @id_politica = @p;',
    @freq_type = 8, @freq_interval = 126, @hora_inicio = 010000;

-- Respaldo del log: cada 15 minutos todo el día
EXEC dbo.sp_ASADA_CrearJob
    @nombre = N'Job_RespaldoLogTransacciones',
    @descripcion = N'ASADA - Respaldo del log de transacciones cada 15 minutos (Point-in-Time).',
    @comando = N'DECLARE @p int = (SELECT TOP (1) p.id_politica FROM dbo.Politica_Respaldo p
                 JOIN dbo.Tipo_Respaldo t ON t.id_tipo_respaldo = p.id_tipo_respaldo
                 WHERE t.nombre_respaldo = ''Log'' AND p.activo = 1 ORDER BY p.id_politica);
                 EXEC dbo.sp_EjecutarRespaldo @id_politica = @p, @verificar = 0;',
    @freq_type = 4, @freq_interval = 1, @hora_inicio = 000000,
    @freq_subday_type = 4, @freq_subday_interval = 15;

-- Carga del Data Warehouse: todos los días a las 02:00
EXEC dbo.sp_ASADA_CrearJob
    @nombre = N'Job_CargaNocturnaDW',
    @descripcion = N'ASADA - Proceso ETL nocturno hacia ASADA_DW (R5).',
    @comando = N'EXEC dbo.sp_EjecutarCargaDW;',
    @freq_type = 4, @freq_interval = 1, @hora_inicio = 020000;

-- Mantenimiento nocturno: todos los días a las 03:00
EXEC dbo.sp_ASADA_CrearJob
    @nombre = N'Job_MantenimientoNocturno',
    @descripcion = N'ASADA - Vencimiento de facturas, recargos por mora, índices, verificación de respaldos e integridad.',
    @comando = N'EXEC dbo.sp_ActualizarFacturasVencidas;
                 EXEC dbo.sp_AplicarRecargosMoraMasivo;
                 EXEC dbo.sp_MantenimientoIndices;
                 EXEC dbo.sp_VerificarIntegridadRespaldos;
                 EXEC dbo.sp_VerificarIntegridadBD;',
    @freq_type = 4, @freq_interval = 1, @hora_inicio = 030000;
GO

SELECT j.name AS job, j.enabled, s.name AS horario
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules s     ON s.schedule_id = js.schedule_id
WHERE j.name LIKE 'Job[_]%'
ORDER BY j.name;
GO
