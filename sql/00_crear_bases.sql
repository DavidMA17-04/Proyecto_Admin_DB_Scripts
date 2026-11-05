SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Script 00: Creación de la base transaccional y del Data Warehouse
   --------------------------------------------------------------------*/

USE master;
GO

-- Tamaños según la estimación a 10 años (sección 14): ASADA 1 GB de datos (máx. 5 GB)
-- y log de 512 MB (máx. 2 GB); ASADA_DW 512 MB de datos (máx. 2 GB) y log de 256 MB (máx. 1 GB)

-- Carpetas de datos/log: variables sqlcmd RutaDatos y RutaLog (ver ejecutar_todo.sql).
-- Solo aplica en instalación nueva; no mueve archivos de bases ya creadas.
EXECUTE master.dbo.xp_create_subdir '$(RutaDatos)';
EXECUTE master.dbo.xp_create_subdir '$(RutaLog)';
GO

   --Base transaccional ASADA
IF DB_ID('ASADA') IS NULL
BEGIN
    CREATE DATABASE ASADA
    ON PRIMARY
    (
        NAME = 'ASADA_Data',
        FILENAME = '$(RutaDatos)\ASADA_Data.mdf',
        --Tamaño del archivo principal (PRIMARY) de ASADA
        SIZE = 64MB,
        MAXSIZE = 256MB,
        FILEGROWTH = 32MB
    )
    LOG ON
    (
        NAME = 'ASADA_Log',
        FILENAME = '$(RutaLog)\ASADA_Log.ldf',
        --Tamaño del log de transacciones de ASADA
        SIZE = 512MB,
        MAXSIZE = 2GB,
        FILEGROWTH = 128MB
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
        FILENAME = '$(RutaDatos)\Abonados_Data.ndf',
        --Tamaño de Abonados_Data (filegroup Abonados)
        SIZE = 128MB,
        MAXSIZE = 512MB,
        FILEGROWTH = 64MB
    ) TO FILEGROUP Abonados;
GO

--facturacion
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.database_files WHERE name = 'Facturacion_Data')
    ALTER DATABASE ASADA
    ADD FILE
    (
        NAME = 'Facturacion_Data',
        FILENAME = '$(RutaDatos)\Facturacion_Data.ndf',
        --Tamaño de Facturacion_Data (filegroup Facturacion)
        SIZE = 384MB,
        MAXSIZE = 2GB,
        FILEGROWTH = 128MB
    ) TO FILEGROUP Facturacion;
GO

--operaciones
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.database_files WHERE name = 'Operaciones_Data')
    ALTER DATABASE ASADA
    ADD FILE
    (
        NAME = 'Operaciones_Data',
        FILENAME = '$(RutaDatos)\Operaciones_Data.ndf',
        --Tamaño de Operaciones_Data (filegroup Operaciones)
        SIZE = 128MB,
        MAXSIZE = 512MB,
        FILEGROWTH = 64MB
    ) TO FILEGROUP Operaciones;
GO

--seguridad
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.database_files WHERE name = 'Seguridad_Data')
    ALTER DATABASE ASADA
    ADD FILE
    (
        NAME = 'Seguridad_Data',
        FILENAME = '$(RutaDatos)\Seguridad_Data.ndf',
        --Tamaño de Seguridad_Data (filegroup Seguridad)
        SIZE = 64MB,
        MAXSIZE = 256MB,
        FILEGROWTH = 32MB
    ) TO FILEGROUP Seguridad;
GO

--auditoria
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.database_files WHERE name = 'Auditoria_Data')
    ALTER DATABASE ASADA
    ADD FILE
    (
        NAME = 'Auditoria_Data',
        FILENAME = '$(RutaDatos)\Auditoria_Data.ndf',
        --Tamaño de Auditoria_Data (filegroup Auditoria)
        SIZE = 192MB,
        MAXSIZE = 1280MB,
        FILEGROWTH = 128MB
    ) TO FILEGROUP Auditoria;
GO

--administracion
IF NOT EXISTS (SELECT 1 FROM ASADA.sys.database_files WHERE name = 'Administracion_Data')
    ALTER DATABASE ASADA
    ADD FILE
    (
        NAME = 'Administracion_Data',
        FILENAME = '$(RutaDatos)\Administracion_Data.ndf',
        --Tamaño de Administracion_Data (filegroup Administracion)
        SIZE = 64MB,
        MAXSIZE = 256MB,
        FILEGROWTH = 32MB
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
        FILENAME = '$(RutaDatos)\ASADA_DW_Data.mdf',
        --Tamaño del archivo principal (PRIMARY) de ASADA_DW
        SIZE = 64MB,
        MAXSIZE = 256MB,
        FILEGROWTH = 32MB
    )
    LOG ON
    (
        NAME = 'ASADA_DW_Log',
        FILENAME = '$(RutaLog)\ASADA_DW_Log.ldf',
        --Tamaño del log de transacciones de ASADA_DW
        SIZE = 256MB,
        MAXSIZE = 1GB,
        FILEGROWTH = 64MB
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
        FILENAME = '$(RutaDatos)\DW_Dimensiones_Data.ndf',
        --Tamaño de DW_Dimensiones_Data (filegroup DW_Dimensiones)
        SIZE = 128MB,
        MAXSIZE = 512MB,
        FILEGROWTH = 64MB
    ) TO FILEGROUP DW_Dimensiones;
GO

--hechos
IF NOT EXISTS (SELECT 1 FROM ASADA_DW.sys.database_files WHERE name = 'DW_Hechos_Data')
    ALTER DATABASE ASADA_DW
    ADD FILE
    (
        NAME = 'DW_Hechos_Data',
        FILENAME = '$(RutaDatos)\DW_Hechos_Data.ndf',
        --Tamaño de DW_Hechos_Data (filegroup DW_Hechos)
        SIZE = 320MB,
        MAXSIZE = 1280MB,
        FILEGROWTH = 64MB
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
