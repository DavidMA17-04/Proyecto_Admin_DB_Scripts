-- Corrige bases ya instaladas: deja todas las direcciones y ubicaciones en el
-- cantón de Santa Cruz (antes había datos de prueba con Nicoya y Mansión).
-- Se puede ejecutar varias veces. En sqlcmd usar -I (QUOTED_IDENTIFIER ON).
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
USE ASADA;
GO

EXEC sp_set_session_context N'comentario', 'Corrección: datos solo del cantón de Santa Cruz';

BEGIN TRAN;

UPDATE dbo.Abonado_Fisico
   SET direccion = 'Santa Cruz, ' + LTRIM(SUBSTRING(direccion, CHARINDEX(',', direccion) + 1, 200))
 WHERE direccion LIKE 'Nicoya,%' OR direccion LIKE 'Mansi_n,%';

UPDATE dbo.Abonado_Juridico
   SET direccion = 'Santa Cruz, ' + LTRIM(SUBSTRING(direccion, CHARINDEX(',', direccion) + 1, 200))
 WHERE direccion LIKE 'Nicoya,%';

UPDATE dbo.Abonado_Juridico
   SET direccion = REPLACE(REPLACE(direccion, 'carretera a Nicoya', 'carretera a Diriá'), 'salida a Nicoya', 'salida a Diriá')
 WHERE direccion LIKE '%Nicoya%';

UPDATE dbo.Conexion
   SET ubicacion = 'Santa Cruz, ' + LTRIM(SUBSTRING(ubicacion, CHARINDEX(',', ubicacion) + 1, 50))
 WHERE ubicacion LIKE 'Nicoya,%' OR ubicacion LIKE 'Mansi_n,%';

UPDATE dbo.Conexion
   SET ubicacion = REPLACE(ubicacion, 'Salida a Nicoya', 'Salida a Diriá')
 WHERE ubicacion LIKE '%Nicoya%';

UPDATE dbo.Incidencia
   SET ubicacion = 'Santa Cruz, ' + LTRIM(SUBSTRING(ubicacion, CHARINDEX(',', ubicacion) + 1, 200))
 WHERE ubicacion LIKE 'Nicoya,%' OR ubicacion LIKE 'Mansi_n,%';

UPDATE i
   SET i.ubicacion = c.ubicacion
  FROM dbo.Incidencia i
  JOIN dbo.Medidor m ON m.id_medidor = i.id_medidor
  JOIN dbo.Conexion c ON c.id_conexion = m.id_conexion
 WHERE i.ubicacion IS NULL OR LTRIM(RTRIM(i.ubicacion)) = '' OR i.ubicacion = '—';

UPDATE dbo.Mantenimiento
   SET descripcion = REPLACE(descripcion, 'AtenciÃ³n', 'Atención')
 WHERE descripcion LIKE '%AtenciÃ³n%';

COMMIT;

-- Refresca distritos en DIM_ABONADO y DIM_CONEXION del data warehouse.
EXEC dbo.sp_ETL_CargarDimensionesDW;
GO
