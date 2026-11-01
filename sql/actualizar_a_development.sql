/* ---------------------------------------------------------------------
   Actualiza una base ASADA ya instalada (versión main) a la rama
   development, sin borrar datos. Se puede ejecutar más de una vez.
   Agrega:
     - Recargo_mora.anulado_manual
     - Tablas Tramo_Mora y Parametro_Mora (con sus valores iniciales)
     - Funciones, vistas y procedimientos de pagos y mora nuevos
     - Filegroups DW_Dimensiones y DW_Hechos (si faltan) sin duplicar archivos
     - DIM_TIPO_INCIDENCIA y FACT_INCIDENCIA (si no existen) y ETL de incidencias
     - Acceso mínimo de motor a ASADA_DW (Rol_LecturaDW / Rol_CargaDW)
     - Default de Incidencia.fecha_modificacion (filas ya guardadas no se tocan)
   No borra ni recrea tablas con datos. Para una instalación nueva use
   ejecutar_todo.sql, no este script.
   Uso: sqlcmd -S localhost -E -C -b -f 65001 -i actualizar_a_development.sql
        (desde la carpeta sql) o en SSMS con modo SQLCMD activado.
   --------------------------------------------------------------------- */
:on error exit
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Filegroups del DW: mismo patrón que 00_crear_bases.sql.
   La carpeta de los .ndf se toma de un archivo de datos ya existente
   de ASADA_DW; no se asume c:\sqldata. */
IF DB_ID('ASADA_DW') IS NULL
    THROW 51001, 'No existe ASADA_DW. Para una instalación nueva use ejecutar_todo.sql.', 1;
GO

IF NOT EXISTS (SELECT 1 FROM ASADA_DW.sys.filegroups WHERE name = 'DW_Dimensiones')
    ALTER DATABASE ASADA_DW ADD FILEGROUP DW_Dimensiones;
GO
IF NOT EXISTS (SELECT 1 FROM ASADA_DW.sys.filegroups WHERE name = 'DW_Hechos')
    ALTER DATABASE ASADA_DW ADD FILEGROUP DW_Hechos;
GO

DECLARE @dir nvarchar(4000), @origen nvarchar(4000), @pos int,
        @sql nvarchar(max), @logico sysname, @ruta nvarchar(4000);

SELECT TOP (1) @origen = physical_name
FROM ASADA_DW.sys.database_files
WHERE type = 0
ORDER BY file_id;

SET @pos = CASE WHEN @origen IS NULL THEN 0 ELSE CHARINDEX('\', REVERSE(@origen)) END;
IF @pos = 0
    THROW 51002, 'No se encontró un archivo de datos de ASADA_DW para ubicar los filegroups nuevos.', 1;
SET @dir = LEFT(@origen, LEN(@origen) - @pos);

IF NOT EXISTS (
    SELECT 1
    FROM ASADA_DW.sys.database_files df
    JOIN ASADA_DW.sys.filegroups fg ON fg.data_space_id = df.data_space_id
    WHERE fg.name = 'DW_Dimensiones')
BEGIN
    SET @logico = N'DW_Dimensiones_Data';
    IF EXISTS (SELECT 1 FROM ASADA_DW.sys.database_files WHERE name = @logico)
        SET @logico = N'DW_Dimensiones_Data_dev';
    SET @ruta = @dir + N'\' + @logico + N'.ndf';
    IF EXISTS (SELECT 1 FROM ASADA_DW.sys.database_files WHERE physical_name = @ruta)
        THROW 51003, 'Ya hay un archivo de ASADA_DW en la ruta calculada para DW_Dimensiones.', 1;
    SET @sql = N'ALTER DATABASE ASADA_DW ADD FILE (NAME = ' + QUOTENAME(@logico, '''')
             + N', FILENAME = ' + QUOTENAME(@ruta, '''')
             + N', SIZE = 50MB, MAXSIZE = 300MB, FILEGROWTH = 25MB) TO FILEGROUP DW_Dimensiones;';
    EXEC sys.sp_executesql @sql;
END

IF NOT EXISTS (
    SELECT 1
    FROM ASADA_DW.sys.database_files df
    JOIN ASADA_DW.sys.filegroups fg ON fg.data_space_id = df.data_space_id
    WHERE fg.name = 'DW_Hechos')
BEGIN
    SET @logico = N'DW_Hechos_Data';
    IF EXISTS (SELECT 1 FROM ASADA_DW.sys.database_files WHERE name = @logico)
        SET @logico = N'DW_Hechos_Data_dev';
    SET @ruta = @dir + N'\' + @logico + N'.ndf';
    IF EXISTS (SELECT 1 FROM ASADA_DW.sys.database_files WHERE physical_name = @ruta)
        THROW 51004, 'Ya hay un archivo de ASADA_DW en la ruta calculada para DW_Hechos.', 1;
    SET @sql = N'ALTER DATABASE ASADA_DW ADD FILE (NAME = ' + QUOTENAME(@logico, '''')
             + N', FILENAME = ' + QUOTENAME(@ruta, '''')
             + N', SIZE = 100MB, MAXSIZE = 1000MB, FILEGROWTH = 50MB) TO FILEGROUP DW_Hechos;';
    EXEC sys.sp_executesql @sql;
END
GO

IF NOT EXISTS (SELECT 1 FROM ASADA_DW.sys.filegroups WHERE name = 'DW_Hechos' AND is_default = 1)
    ALTER DATABASE ASADA_DW MODIFY FILEGROUP DW_Hechos DEFAULT;
GO

USE ASADA;
GO

IF OBJECT_ID('dbo.DF_Incidencia_FechaMod', 'D') IS NULL
    ALTER TABLE dbo.Incidencia
        ADD CONSTRAINT DF_Incidencia_FechaMod DEFAULT (GETDATE()) FOR fecha_modificacion;
GO

IF COL_LENGTH('dbo.Recargo_mora', 'anulado_manual') IS NULL
    ALTER TABLE dbo.Recargo_mora
        ADD anulado_manual bit NOT NULL CONSTRAINT DF_RecargoMora_AnuladoManual DEFAULT 0;
GO

IF OBJECT_ID('dbo.Tramo_Mora', 'U') IS NULL
CREATE TABLE dbo.Tramo_Mora (
    id_tramo    int IDENTITY(1,1) NOT NULL,
    dias_desde  int           NOT NULL,
    dias_hasta  int           NULL,
    porcentaje  decimal(5,2)  NOT NULL,
    activo      bit           NOT NULL CONSTRAINT DF_TramoMora_Activo DEFAULT (1),
    CONSTRAINT PK_Tramo_Mora PRIMARY KEY (id_tramo),
    CONSTRAINT CK_TramoMora_Dias CHECK (dias_desde > 0 AND (dias_hasta IS NULL OR dias_hasta >= dias_desde)),
    CONSTRAINT CK_TramoMora_Porcentaje CHECK (porcentaje > 0 AND porcentaje <= 100)
) ON Facturacion;
GO

IF OBJECT_ID('dbo.Parametro_Mora', 'U') IS NULL
CREATE TABLE dbo.Parametro_Mora (
    nombre              varchar(50)   NOT NULL,
    valor               decimal(12,2) NOT NULL,
    descripcion         varchar(200)  NULL,
    fecha_modificacion  datetime      NOT NULL CONSTRAINT DF_ParametroMora_Fecha DEFAULT (GETDATE()),
    CONSTRAINT PK_Parametro_Mora PRIMARY KEY (nombre),
    CONSTRAINT CK_ParametroMora_Valor CHECK (valor >= 0)
) ON Administracion;
GO

-- Mismos valores que 16_datos_iniciales.sql (los porcentajes que antes estaban fijos en la función).
IF NOT EXISTS (SELECT 1 FROM dbo.Tramo_Mora)
    INSERT INTO dbo.Tramo_Mora (dias_desde, dias_hasta, porcentaje) VALUES
        (1,  30,   2.00),
        (31, 60,   4.00),
        (61, NULL, 6.00);

INSERT INTO dbo.Parametro_Mora (nombre, valor, descripcion)
SELECT v.nombre, v.valor, v.descripcion
FROM (VALUES
    ('dias_mora_suspension',    90, 'Días de atraso a partir de los cuales se suspende la conexión'),
    ('saldo_minimo_suspension',  0, 'Monto vencido mínimo (colones) para suspender una conexión'),
    ('plazo_pago_dias',         15, 'Días de plazo para pagar una factura desde su emisión')
) v (nombre, valor, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Parametro_Mora p WHERE p.nombre = v.nombre);
GO

-- De 03_funciones.sql solo cambió esta función. El script completo no se puede
-- volver a ejecutar: algunas funciones las usan restricciones CHECK de las tablas.
CREATE OR ALTER FUNCTION dbo.fn_CalcularPorcentajeMora (@dias_atraso int)
RETURNS decimal(5,2)
AS
BEGIN
    DECLARE @porcentaje decimal(5,2);

    IF @dias_atraso <= 0 RETURN 0;

    SELECT TOP (1) @porcentaje = t.porcentaje
    FROM dbo.Tramo_Mora t
    WHERE t.activo = 1
      AND t.dias_desde <= @dias_atraso
      AND (t.dias_hasta IS NULL OR t.dias_hasta >= @dias_atraso)
    ORDER BY t.dias_desde DESC;

    RETURN ISNULL(@porcentaje, 0);
END;
GO

-- Estos scripts solo usan CREATE OR ALTER (13 crea DIM/FACT de incidencias
-- solo si no existen; no borra tablas con datos).
:r 04_vistas.sql
:r 07_procedimientos_pagos_mora.sql
:r 13_data_warehouse.sql
:r 14_triggers.sql
:r 18_pruebas.sql
:r 15_acceso_dw.sql

PRINT 'Base ASADA actualizada a development.';
GO
