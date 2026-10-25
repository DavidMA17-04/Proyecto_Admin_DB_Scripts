SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Script 15: Administración de la BD (RA4) y roles de base de datos (RA1, RA3)
   ===================================================================== */
USE ASADA;
GO

/* ---------------------------------------------------------------------
   12.32 Mantenimiento y monitoreo
   --------------------------------------------------------------------- */
-- Reorganiza (5 % a 30 %) o reconstruye (más de 30 %) los índices fragmentados
-- y actualiza estadísticas. Con @solo_reporte = 1 solo muestra la fragmentación.
CREATE OR ALTER PROCEDURE dbo.sp_MantenimientoIndices
    @umbral_reorganizar  decimal(5,2) = 5,
    @umbral_reconstruir  decimal(5,2) = 30,
    @paginas_minimas     int          = 8,
    @solo_reporte        bit          = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql nvarchar(max), @tabla nvarchar(300), @indice sysname, @frag decimal(5,2), @accion varchar(15),
            @reorganizados int = 0, @reconstruidos int = 0, @desc varchar(max);

    SELECT QUOTENAME(s.name) + '.' + QUOTENAME(t.name) AS tabla, i.name AS indice,
           CAST(ps.avg_fragmentation_in_percent AS decimal(5,2)) AS fragmentacion, ps.page_count AS paginas,
           CASE WHEN ps.avg_fragmentation_in_percent >= @umbral_reconstruir THEN 'RECONSTRUIR'
                WHEN ps.avg_fragmentation_in_percent >= @umbral_reorganizar THEN 'REORGANIZAR'
                ELSE 'NINGUNA' END AS accion
    INTO #frag
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
    JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
    JOIN sys.tables  t ON t.object_id = ps.object_id
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE i.index_id > 0 AND ps.page_count >= @paginas_minimas;

    IF @solo_reporte = 1
    BEGIN
        SELECT * FROM #frag ORDER BY fragmentacion DESC;
        RETURN;
    END

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT tabla, indice, fragmentacion, accion FROM #frag WHERE accion <> 'NINGUNA';

    OPEN cur;
    FETCH NEXT FROM cur INTO @tabla, @indice, @frag, @accion;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = CONCAT(N'ALTER INDEX ', QUOTENAME(@indice), N' ON ', @tabla,
                          IIF(@accion = 'RECONSTRUIR', N' REBUILD;', N' REORGANIZE;'));
        EXEC sys.sp_executesql @sql;

        IF @accion = 'RECONSTRUIR' SET @reconstruidos += 1; ELSE SET @reorganizados += 1;
        FETCH NEXT FROM cur INTO @tabla, @indice, @frag, @accion;
    END
    CLOSE cur;
    DEALLOCATE cur;

    EXEC sys.sp_updatestats;

    SET @desc = CONCAT('Mantenimiento de índices: ', @reorganizados, ' reorganizados, ', @reconstruidos,
                       ' reconstruidos. Estadísticas actualizadas.');
    EXEC dbo.sp_RegistrarEventoBitacora 'MANTENIMIENTO', NULL, @desc;

    SELECT @reorganizados AS indices_reorganizados, @reconstruidos AS indices_reconstruidos;
END;
GO

-- Ejecuta DBCC CHECKDB y registra el resultado en la bitácora.
CREATE OR ALTER PROCEDURE dbo.sp_VerificarIntegridadBD
    @base sysname = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @inicio datetime = GETDATE(), @desc varchar(max);
    SET @base = ISNULL(@base, DB_NAME());

    BEGIN TRY
        DBCC CHECKDB (@base) WITH NO_INFOMSGS, ALL_ERRORMSGS;

        SET @desc = CONCAT('DBCC CHECKDB sobre ', @base, ' sin errores (', DATEDIFF(SECOND, @inicio, GETDATE()), ' s).');
        EXEC dbo.sp_RegistrarEventoBitacora 'MANTENIMIENTO', NULL, @desc;

        SELECT @base AS base_datos, 'Sin errores de integridad' AS resultado, DATEDIFF(SECOND, @inicio, GETDATE()) AS segundos;
    END TRY
    BEGIN CATCH
        SET @desc = CONCAT('DBCC CHECKDB sobre ', @base, ' reportó errores: ', ERROR_MESSAGE());
        EXEC dbo.sp_RegistrarEventoBitacora 'ALERTA', NULL, @desc;

        SELECT @base AS base_datos, 'Con errores' AS resultado, ERROR_MESSAGE() AS detalle;
    END CATCH
END;
GO

-- RA4: espacio, consultas más costosas y estado de los respaldos y del ETL.
CREATE OR ALTER PROCEDURE dbo.sp_MonitorearBD
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Uso de espacio por archivo
    SELECT df.name AS archivo, df.type_desc AS tipo,
           ISNULL(fg.name, 'LOG') AS filegroup,
           CAST(df.size / 128.0 AS decimal(10,2)) AS tamano_mb,
           CAST(FILEPROPERTY(df.name, 'SpaceUsed') / 128.0 AS decimal(10,2)) AS usado_mb,
           CAST((df.size - FILEPROPERTY(df.name, 'SpaceUsed')) / 128.0 AS decimal(10,2)) AS libre_mb,
           CASE WHEN df.max_size = -1 THEN NULL ELSE CAST(df.max_size / 128.0 AS decimal(10,2)) END AS maximo_mb,
           CASE WHEN df.is_percent_growth = 1 THEN CONCAT(df.growth, '%')
                ELSE CONCAT(df.growth / 128, 'MB') END AS crecimiento
    FROM sys.database_files df
    LEFT JOIN sys.filegroups fg ON fg.data_space_id = df.data_space_id;

    -- 2. Tablas más grandes
    SELECT TOP (10) t.name AS tabla, SUM(p.rows) AS filas,
           CAST(SUM(a.total_pages) / 128.0 AS decimal(10,2)) AS espacio_mb
    FROM sys.tables t
    JOIN sys.partitions p       ON p.object_id = t.object_id AND p.index_id IN (0, 1)
    JOIN sys.allocation_units a ON a.container_id = p.partition_id
    GROUP BY t.name
    ORDER BY espacio_mb DESC;

    -- 3. Consultas con mayor tiempo promedio (requiere VIEW SERVER STATE)
    BEGIN TRY
        SELECT TOP (10)
               qs.execution_count AS ejecuciones,
               CAST(qs.total_elapsed_time / qs.execution_count / 1000.0 AS decimal(12,2)) AS ms_promedio,
               OBJECT_NAME(st.objectid, st.dbid) AS objeto,
               LEFT(st.text, 200) AS consulta
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        WHERE st.dbid = DB_ID()
        ORDER BY ms_promedio DESC;
    END TRY
    BEGIN CATCH
        SELECT 'Sin permiso VIEW SERVER STATE para ver estadísticas de consultas.' AS aviso;
    END CATCH

    -- 4. Último respaldo por tipo
    SELECT t.nombre_respaldo AS tipo,
           MAX(CASE WHEN h.estado = 'Exitoso' THEN h.fecha_inicio END) AS ultimo_respaldo_exitoso,
           DATEDIFF(HOUR, MAX(CASE WHEN h.estado = 'Exitoso' THEN h.fecha_inicio END), GETDATE()) AS horas_desde_ultimo,
           SUM(CASE WHEN h.estado = 'Fallido' AND h.fecha_inicio >= DATEADD(DAY, -7, GETDATE()) THEN 1 ELSE 0 END) AS fallidos_7_dias
    FROM dbo.Tipo_Respaldo t
    LEFT JOIN dbo.Politica_Respaldo p  ON p.id_tipo_respaldo = t.id_tipo_respaldo
    LEFT JOIN dbo.Historial_Respaldo h ON h.id_politica = p.id_politica
    GROUP BY t.nombre_respaldo;

    -- 5. Estado del ETL
    SELECT * FROM dbo.vw_UltimaCargaPorTabla;
END;
GO

/* ---------------------------------------------------------------------
   Roles de base de datos (permisos del motor)
   La aplicación ejecuta procedimientos; ningún rol operativo recibe permisos
   directos sobre las tablas (el encadenamiento de propiedad de dbo da el acceso).
   --------------------------------------------------------------------- */
IF DATABASE_PRINCIPAL_ID('Rol_Operador')         IS NULL CREATE ROLE Rol_Operador;          -- Administrador del Sistema
IF DATABASE_PRINCIPAL_ID('Rol_Fontanero')        IS NULL CREATE ROLE Rol_Fontanero;         -- Personal de campo
IF DATABASE_PRINCIPAL_ID('Rol_JuntaDirectiva')   IS NULL CREATE ROLE Rol_JuntaDirectiva;    -- Consulta de reportes
IF DATABASE_PRINCIPAL_ID('Rol_Auditoria')        IS NULL CREATE ROLE Rol_Auditoria;         -- Consulta de bitácora
IF DATABASE_PRINCIPAL_ID('Rol_OperadorRespaldo') IS NULL CREATE ROLE Rol_OperadorRespaldo;  -- Respaldos
IF DATABASE_PRINCIPAL_ID('Rol_DBA')              IS NULL CREATE ROLE Rol_DBA;               -- Administración completa
GO

-- Rol_DBA: administración completa de la base.
ALTER ROLE db_owner ADD MEMBER Rol_DBA;
GO

-- Rol_Operador: puede ejecutar todos los procedimientos y leer las vistas,
-- excepto los de respaldo, restauración, ETL y mantenimiento técnico (son del DBA).
GRANT EXECUTE ON SCHEMA::dbo TO Rol_Operador;
GRANT SELECT  ON SCHEMA::dbo TO Rol_Operador;
DENY SELECT ON dbo.Usuario_Sistema TO Rol_Operador;   -- protege los hashes de contraseñas
DENY EXECUTE ON dbo.sp_EjecutarRespaldo               TO Rol_Operador;
DENY EXECUTE ON dbo.sp_RestaurarPuntoEnTiempo         TO Rol_Operador;
DENY EXECUTE ON dbo.sp_VerificarIntegridadRespaldos   TO Rol_Operador;
DENY EXECUTE ON dbo.sp_GestionarPoliticaRespaldo      TO Rol_Operador;
DENY EXECUTE ON dbo.sp_MantenimientoIndices           TO Rol_Operador;
DENY EXECUTE ON dbo.sp_VerificarIntegridadBD          TO Rol_Operador;
DENY EXECUTE ON dbo.sp_EjecutarCargaDW                TO Rol_Operador;
DENY EXECUTE ON dbo.sp_ReintentarCargaETL             TO Rol_Operador;
-- Los DENY de sp_CargarDatosPrueba y sp_LimpiarDatosPrueba están en el script 18.
GO

-- Rol_Fontanero: lecturas, incidencias y sus mantenimientos asignados.
GRANT EXECUTE ON dbo.sp_IniciarSesion                    TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_CerrarSesion                     TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_CambiarContrasenaUsuario         TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_RegistrarLectura                 TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_ConsultarMedidores               TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_RegistrarIncidente               TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_ConsultarTiposIncidencia         TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_ConsultarMantenimientos          TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_CambiarEstadoMantenimiento       TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_CerrarMantenimiento              TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_EmpleadoMantenimiento            TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_ConsultarHistorialMantenimiento  TO Rol_Fontanero;
GRANT EXECUTE ON dbo.sp_ConsultarTiposTrabajo            TO Rol_Fontanero;
GRANT SELECT  ON dbo.vw_MedidorNoLeido                   TO Rol_Fontanero;
GRANT SELECT  ON dbo.vw_MantenimientosPendientes         TO Rol_Fontanero;
GO

-- Rol_Auditoria: consulta la bitácora sin poder modificar datos operativos.
GRANT SELECT  ON dbo.Bitacora                   TO Rol_Auditoria;
GRANT SELECT  ON dbo.vw_BitacoraReciente        TO Rol_Auditoria;
GRANT EXECUTE ON dbo.sp_ConsultarBitacora       TO Rol_Auditoria;
GRANT EXECUTE ON dbo.sp_ResumirActividadUsuarios TO Rol_Auditoria;
GO

-- Rol_JuntaDirectiva: reportes de gestión, bitácora y Data Warehouse (solo lectura).
ALTER ROLE Rol_Auditoria ADD MEMBER Rol_JuntaDirectiva;
GRANT EXECUTE ON dbo.sp_IniciarSesion              TO Rol_JuntaDirectiva;
GRANT EXECUTE ON dbo.sp_CerrarSesion               TO Rol_JuntaDirectiva;
GRANT EXECUTE ON dbo.sp_GenerarReporteMorosidad    TO Rol_JuntaDirectiva;
GRANT EXECUTE ON dbo.sp_HistorialConsumo           TO Rol_JuntaDirectiva;
GRANT EXECUTE ON dbo.sp_ConsultarFacturas          TO Rol_JuntaDirectiva;
GRANT EXECUTE ON dbo.sp_ConsultarMantenimientos    TO Rol_JuntaDirectiva;
GRANT EXECUTE ON dbo.sp_ConsultarIncidencias       TO Rol_JuntaDirectiva;
GRANT EXECUTE ON dbo.sp_SimularMontoConTarifa      TO Rol_JuntaDirectiva;
GRANT EXECUTE ON dbo.sp_ConciliarOrigenDW          TO Rol_JuntaDirectiva;
GRANT SELECT  ON dbo.vw_UsuariosMorosos            TO Rol_JuntaDirectiva;
GRANT SELECT  ON dbo.vw_ResumenConsumoMensual      TO Rol_JuntaDirectiva;
GRANT SELECT  ON dbo.vw_PagosPorMetodo             TO Rol_JuntaDirectiva;
GRANT SELECT  ON dbo.vw_IncidentesAbiertos         TO Rol_JuntaDirectiva;
GRANT SELECT  ON dbo.vw_MantenimientosPendientes   TO Rol_JuntaDirectiva;
GRANT SELECT  ON dbo.vw_AlertasActivas             TO Rol_JuntaDirectiva;
GO

-- Rol_OperadorRespaldo: ejecuta y consulta respaldos.
ALTER ROLE db_backupoperator ADD MEMBER Rol_OperadorRespaldo;
GRANT EXECUTE ON dbo.sp_EjecutarRespaldo               TO Rol_OperadorRespaldo;
GRANT EXECUTE ON dbo.sp_VerificarIntegridadRespaldos   TO Rol_OperadorRespaldo;
GRANT EXECUTE ON dbo.sp_ConsultarHistorialRespaldos    TO Rol_OperadorRespaldo;
GRANT EXECUTE ON dbo.sp_ConsultarHistorialRestauracion TO Rol_OperadorRespaldo;
GRANT EXECUTE ON dbo.sp_ConsultarTiposRespaldo         TO Rol_OperadorRespaldo;
GRANT SELECT  ON dbo.Historial_Respaldo                TO Rol_OperadorRespaldo;
GRANT SELECT  ON dbo.Politica_Respaldo                 TO Rol_OperadorRespaldo;
GO

/* ---------------------------------------------------------------------
   Data Warehouse: lectura para la Junta Directiva
   --------------------------------------------------------------------- */
USE ASADA_DW;
GO
IF DATABASE_PRINCIPAL_ID('Rol_LecturaDW') IS NULL CREATE ROLE Rol_LecturaDW;
GRANT SELECT ON SCHEMA::dbo TO Rol_LecturaDW;
GO

/* ---------------------------------------------------------------------
   Ejemplo de logins (ejecutar como sysadmin y cambiar las contraseñas):

   USE master;
   CREATE LOGIN app_asada   WITH PASSWORD = 'Cambiar#Esta1', CHECK_POLICY = ON;
   CREATE LOGIN dba_asada   WITH PASSWORD = 'Cambiar#Esta2', CHECK_POLICY = ON;
   CREATE LOGIN junta_asada WITH PASSWORD = 'Cambiar#Esta3', CHECK_POLICY = ON;

   USE ASADA;
   CREATE USER app_asada   FOR LOGIN app_asada;   ALTER ROLE Rol_Operador       ADD MEMBER app_asada;
   CREATE USER dba_asada   FOR LOGIN dba_asada;   ALTER ROLE Rol_DBA            ADD MEMBER dba_asada;
   CREATE USER junta_asada FOR LOGIN junta_asada; ALTER ROLE Rol_JuntaDirectiva ADD MEMBER junta_asada;

   USE ASADA_DW;
   CREATE USER junta_asada FOR LOGIN junta_asada; ALTER ROLE Rol_LecturaDW ADD MEMBER junta_asada;
   --------------------------------------------------------------------- */
