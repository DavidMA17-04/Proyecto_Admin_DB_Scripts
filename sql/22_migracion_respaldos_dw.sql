/* ---------------------------------------------------------------------
   Migración incremental: políticas de respaldo por base (ASADA / ASADA_DW).
   Idempotente. No borra historial ni recrea tablas.
   Uso: sqlcmd -S localhost -E -C -b -f 65001 -i 22_migracion_respaldos_dw.sql
   --------------------------------------------------------------------- */
:on error exit
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

:setvar RutaRespaldosASADA_DW "C:\Respaldos\ASADA_DW\"

USE ASADA;
GO

IF DB_ID('ASADA_DW') IS NULL
    THROW 51020, 'No existe ASADA_DW. Verifique la instalación antes de migrar respaldos del DW.', 1;
GO

IF COL_LENGTH('dbo.Politica_Respaldo', 'nombre_base') IS NULL
BEGIN
    ALTER TABLE dbo.Politica_Respaldo
        ADD nombre_base sysname NOT NULL
            CONSTRAINT DF_PoliticaRespaldo_Base_Mig DEFAULT ('ASADA');
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_PoliticaRespaldo_Base' AND parent_object_id = OBJECT_ID('dbo.Politica_Respaldo'))
BEGIN
    ALTER TABLE dbo.Politica_Respaldo
        ADD CONSTRAINT CK_PoliticaRespaldo_Base CHECK (nombre_base IN ('ASADA', 'ASADA_DW'));
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM dbo.Politica_Respaldo
    WHERE nombre_base = 'ASADA_DW'
      AND nombre_politica = N'Respaldo completo diario ASADA_DW')
BEGIN
    INSERT INTO dbo.Politica_Respaldo (id_tipo_respaldo, nombre_base, nombre_politica, frecuencia, hora_ejecucion, retencion_dias, ruta_destino)
    SELECT t.id_tipo_respaldo, 'ASADA_DW', N'Respaldo completo diario ASADA_DW', N'Diario (post-ETL)', '02:30', 14, N'$(RutaRespaldosASADA_DW)'
    FROM dbo.Tipo_Respaldo t
    WHERE t.nombre_respaldo = 'Completo';
END;
GO

:r 12_procedimientos_respaldos.sql

PRINT 'Migración 22: respaldos multibase aplicada.';
GO
