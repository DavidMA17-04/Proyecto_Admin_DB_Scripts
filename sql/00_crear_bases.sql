SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Proyecto: Sistema de Gestión para una ASADA
   Curso:    Administración de Bases de Datos - UNA, Campus Nicoya
   Motor:    Microsoft SQL Server 2019 o superior
   Script 00: Creación de la base transaccional y del Data Warehouse
   ---------------------------------------------------------------------
   Orden de ejecución de los scripts:
     00_crear_bases.sql
     01_tablas.sql
     02_indices.sql
     03_funciones.sql
     04_vistas.sql
     05_procedimientos_abonados_conexiones.sql
     06_procedimientos_lecturas_facturacion.sql
     07_procedimientos_pagos_mora.sql
     08_procedimientos_incidencias_mantenimiento.sql
     09_procedimientos_seguridad_bitacora.sql
     10_procedimientos_catalogos.sql
     11_procedimientos_consumo_anomalo.sql
     12_procedimientos_respaldos.sql
     13_data_warehouse.sql
     14_triggers.sql
     15_administracion_y_roles_bd.sql
     16_datos_iniciales.sql
     17_jobs_sql_agent.sql        (requiere SQL Server Agent; no aplica en Express)
     18_pruebas.sql
   O bien abrir ejecutar_todo.sql en modo SQLCMD.
   ---------------------------------------------------------------------
   Distribución física de la base ASADA
     Archivo de datos principal (PRIMARY) y de log con tamaño inicial,
     tamaño máximo y crecimiento fijos. Las tablas se reparten en
     filegroups según el módulo al que pertenecen:

     Filegroup        Archivo                  Tablas
     ---------------  -----------------------  ------------------------------
     Abonados (DEF.)  Abonados_Data.ndf        Abonado_Fisico, Abonado_Juridico,
                                               Conexion, Medidor
     Facturacion      Facturacion_Data.ndf     Tipo_Tarifa, Tarifa, Lectura,
                                               Factura, Recargo_mora,
                                               Metodo_Pago, Pago
     Operaciones      Operaciones_Data.ndf     Tipo_Incidencia, Incidencia,
                                               Tipo_Trabajo, Mantenimiento,
                                               Nivel_alerta_Consumo,
                                               Regla_consumo, Alerta_Consumo
     Seguridad        Seguridad_Data.ndf       Empleado, Rol, Modulo, Permiso,
                                               Rol_permiso, Usuario_Sistema
     Auditoria        Auditoria_Data.ndf       Bitacora, Historial_Tarifa,
                                               Historial_Incidencia,
                                               Historial_Mantenimiento
     Administracion   Administracion_Data.ndf  Tipo_Respaldo, Politica_Respaldo,
                                               Historial_Respaldo,
                                               Historial_Restauracion,
                                               Control_ETL

   Criterio de tamaños: Facturacion y Auditoria son los que más crecen
   (una lectura y una factura por conexión cada mes, y una fila de
   bitácora por cada cambio), por eso tienen más espacio inicial y máximo.
   Seguridad y Administracion son casi catálogos y crecen poco.
   ===================================================================== */
USE master;
GO

-- Carpetas de los archivos de datos y de log (las crea la cuenta del
-- servicio de SQL Server, así queda con permiso de escritura).
EXECUTE master.dbo.xp_create_subdir 'c:\sqldata';
EXECUTE master.dbo.xp_create_subdir 'c:\sqllog';
GO

/* ---------------------------------------------------------------------
   Base transaccional ASADA
   --------------------------------------------------------------------- */
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
-- transacciones y poder restaurar a un punto en el tiempo (R10).
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
                     DIM_TIPO_TRABAJO, DIM_EMPLEADO
     DW_Hechos (DEF.): FACT_CONSUMO, FACT_FACTURACION, FACT_PAGO,
                     FACT_MOROSIDAD, FACT_MANTENIMIENTO
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
