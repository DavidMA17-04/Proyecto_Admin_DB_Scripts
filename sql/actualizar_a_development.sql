/* ---------------------------------------------------------------------
   Actualiza una base ASADA ya instalada (versión main) a la rama
   development, sin borrar datos. Se puede ejecutar más de una vez.
   Agrega:
     - Recargo_mora.anulado_manual
     - Tablas Tramo_Mora y Parametro_Mora (con sus valores iniciales)
     - Funciones, vistas y procedimientos de pagos y mora nuevos
   Uso: sqlcmd -S localhost -E -C -b -f 65001 -i actualizar_a_development.sql
        (desde la carpeta sql) o en SSMS con modo SQLCMD activado.
   --------------------------------------------------------------------- */
:on error exit
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE ASADA;
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

-- Estos scripts solo usan CREATE OR ALTER, así que se pueden volver a ejecutar.
:r 04_vistas.sql
:r 07_procedimientos_pagos_mora.sql

PRINT 'Base ASADA actualizada a development.';
GO
