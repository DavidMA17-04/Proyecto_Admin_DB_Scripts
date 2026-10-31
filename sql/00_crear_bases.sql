SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Script 00: Creación de la base transaccional y del Data Warehouse
   --------------------------------------------------------------------*/

USE master;
GO

-- Carpetas de los archivos de datos y de log 
EXECUTE master.dbo.xp_create_subdir 'c:\sqldata';
EXECUTE master.dbo.xp_create_subdir 'c:\sqllog';
GO

   --Base transaccional ASADA
IF DB_ID('ASADA') IS NULL
BEGIN
    CREATE DATABASE ASADA
    ON PRIMARY
    (
        NAME = 'ASADA_Data',
        FILENAME = 'c:\sqldata\ASADA_Data.mdf',
        SIZE = 100MB,
        MAXSIZE = 500MB,
        FILEGROWTH = 25MB
    )
    LOG ON
    (
        NAME = 'ASADA_Log',
        FILENAME = 'c:\sqllog\ASADA_Log.ldf',
        SIZE = 100MB,
        MAXSIZE = 500MB,
        FILEGROWTH = 25MB
    );
END
GO

EXECUTE sp_helpdb ASADA;
GO

-- El modelo de recuperación FULL es obligatorio para respaldar el log de
-- transacciones y poder restaurar a un punto en el tiempo 
ALTER DATABASE ASADA SET RECOVERY FULL;
GO

------------------------------------------------------------- filegroups
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.filegroups WHERE name = 'Abonados')
    ALTER DATABASE ASADA ADD FILEGROUP Abonados;
GO
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.filegroups WHERE name = 'Facturacion')
    ALTER DATABASE ASADA ADD FILEGROUP Facturacion;
GO
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.filegroups WHERE name = 'Operaciones')
    ALTER DATABASE ASADA ADD FILEGROUP Operaciones;
GO
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.filegroups WHERE name = 'Seguridad')
    ALTER DATABASE ASADA ADD FILEGROUP Seguridad;
GO
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.filegroups WHERE name = 'Auditoria')
    ALTER DATABASE ASADA ADD FILEGROUP Auditoria;
GO
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.filegroups WHERE name = 'Administracion')
    ALTER DATABASE ASADA ADD FILEGROUP Administracion;
GO

------------------------------------------------- archivos de cada filegroup
--abonados
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.database_files WHERE name = 'Abonados_Data')
    ALTER DATABASE ASADA
    ADD FILE
    (
        NAME = 'Abonados_Data',
        FILENAME = 'c:\sqldata\Abonados_Data.ndf',
        SIZE = 100MB,
        MAXSIZE = 700MB,
        FILEGROWTH = 50MB
    ) TO FILEGROUP Abonados;
GO

--facturacion
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.database_files WHERE name = 'Facturacion_Data')
    ALTER DATABASE ASADA
    ADD FILE
    (
        NAME = 'Facturacion_Data',
        FILENAME = 'c:\sqldata\Facturacion_Data.ndf',
        SIZE = 150MB,
        MAXSIZE = 1000MB,
        FILEGROWTH = 50MB
    ) TO FILEGROUP Facturacion;
GO

--operaciones
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.database_files WHERE name = 'Operaciones_Data')
    ALTER DATABASE ASADA
    ADD FILE
    (
        NAME = 'Operaciones_Data',
        FILENAME = 'c:\sqldata\Operaciones_Data.ndf',
        SIZE = 80MB,
        MAXSIZE = 500MB,
        FILEGROWTH = 50MB
    ) TO FILEGROUP Operaciones;
GO

--seguridad
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.database_files WHERE name = 'Seguridad_Data')
    ALTER DATABASE ASADA
    ADD FILE
    (
        NAME = 'Seguridad_Data',
        FILENAME = 'c:\sqldata\Seguridad_Data.ndf',
        SIZE = 50MB,
        MAXSIZE = 300MB,
        FILEGROWTH = 25MB
    ) TO FILEGROUP Seguridad;
GO

--auditoria
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.database_files WHERE name = 'Auditoria_Data')
    ALTER DATABASE ASADA
    ADD FILE
    (
        NAME = 'Auditoria_Data',
        FILENAME = 'c:\sqldata\Auditoria_Data.ndf',
        SIZE = 100MB,
        MAXSIZE = 1000MB,
        FILEGROWTH = 50MB
    ) TO FILEGROUP Auditoria;
GO

--administracion
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.database_files WHERE name = 'Administracion_Data')
    ALTER DATABASE ASADA
    ADD FILE
    (
        NAME = 'Administracion_Data',
        FILENAME = 'c:\sqldata\Administracion_Data.ndf',
        SIZE = 50MB,
        MAXSIZE = 300MB,
        FILEGROWTH = 25MB
    ) TO FILEGROUP Administracion;
GO

------------------------------------------------ abonados como default
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.filegroups WHERE name = 'Abonados' AND is_default = 1)
    ALTER DATABASE ASADA MODIFY FILEGROUP Abonados DEFAULT;
GO

USE ASADA;
GO
EXECUTE sp_helpfilegroup;   --para verificar
GO
USE master;
GO

/* ---------------------------------------------------------------------
   Data Warehouse ASADA_DW
     DW_Dimensiones: DIM_TIEMPO, DIM_ABONADO, DIM_CONEXION, DIM_TARIFA,
                     DIM_TIPO_TRABAJO, DIM_TIPO_INCIDENCIA, DIM_EMPLEADO
     DW_Hechos (DEF.): FACT_CONSUMO, FACT_FACTURACION, FACT_PAGO,
                     FACT_MOROSIDAD, FACT_MANTENIMIENTO, FACT_INCIDENCIA
   Los hechos crecen con cada carga del ETL; las dimensiones casi no.
   --------------------------------------------------------------------- */
IF DB_ID('ASADA_DW') IS NULL
BEGIN
    CREATE DATABASE ASADA_DW
    ON PRIMARY
    (
        NAME = 'ASADA_DW_Data',
        FILENAME = 'c:\sqldata\ASADA_DW_Data.mdf',
        SIZE = 50MB,
        MAXSIZE = 300MB,
        FILEGROWTH = 25MB
    )
    LOG ON
    (
        NAME = 'ASADA_DW_Log',
        FILENAME = 'c:\sqllog\ASADA_DW_Log.ldf',
        SIZE = 50MB,
        MAXSIZE = 300MB,
        FILEGROWTH = 25MB
    );
END
GO

-- El Data Warehouse se recarga desde el origen, por lo que basta el modelo SIMPLE.
ALTER DATABASE ASADA_DW SET RECOVERY SIMPLE;
GO

IF NOT EXISTS (SELECT 1 FROM ASADA_DW.sys.filegroups WHERE name = 'DW_Dimensiones')
    ALTER DATABASE ASADA_DW ADD FILEGROUP DW_Dimensiones;
GO
IF NOT EXISTS (SELECT 1 FROM ASADA_DW.sys.filegroups WHERE name = 'DW_Hechos')
    ALTER DATABASE ASADA_DW ADD FILEGROUP DW_Hechos;
GO

--dimensiones
IF NOT EXISTS (SELECT 1 FROM ASADA_DW.sys.database_files WHERE name = 'DW_Dimensiones_Data')
    ALTER DATABASE ASADA_DW
    ADD FILE
    (
        NAME = 'DW_Dimensiones_Data',
        FILENAME = 'c:\sqldata\DW_Dimensiones_Data.ndf',
        SIZE = 50MB,
        MAXSIZE = 300MB,
        FILEGROWTH = 25MB
    ) TO FILEGROUP DW_Dimensiones;
GO

--hechos
IF NOT EXISTS (SELECT 1 FROM ASADA_DW.sys.database_files WHERE name = 'DW_Hechos_Data')
    ALTER DATABASE ASADA_DW
    ADD FILE
    (
        NAME = 'DW_Hechos_Data',
        FILENAME = 'c:\sqldata\DW_Hechos_Data.ndf',
        SIZE = 100MB,
        MAXSIZE = 1000MB,
        FILEGROWTH = 50MB
    ) TO FILEGROUP DW_Hechos;
GO

IF NOT EXISTS (SELECT 1 FROM ASADA_DW.sys.filegroups WHERE name = 'DW_Hechos' AND is_default = 1)
    ALTER DATABASE ASADA_DW MODIFY FILEGROUP DW_Hechos DEFAULT;
GO

USE ASADA_DW;
GO
EXECUTE sp_helpfilegroup;   --para verificar
GO
USE master;
GO
