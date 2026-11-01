SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Acceso de motor a ASADA_DW.

   Rol_LecturaDW: SELECT (reportes GET /dw/).
   Rol_CargaDW:   SELECT, INSERT, UPDATE, DELETE (escritura del ETL).
   La carga no se asigna sola: el administrador agrega el login real
   con ALTER ROLE, como en el ejemplo de abajo.

   En ASADA el ETL lo ejecuta Rol_DBA (db_owner) o un sysadmin.
   Rol_Operador tiene DENY sobre el orquestador, el reintento y los
   sp_ETL_* (script 15). Los usuarios de React no se tocan.
   --------------------------------------------------------------------- */
USE ASADA_DW;
GO

IF DATABASE_PRINCIPAL_ID('Rol_LecturaDW') IS NULL CREATE ROLE Rol_LecturaDW;
IF DATABASE_PRINCIPAL_ID('Rol_CargaDW')   IS NULL CREATE ROLE Rol_CargaDW;
GRANT SELECT ON SCHEMA::dbo TO Rol_LecturaDW;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO Rol_CargaDW;
GO

-- Quita el mapeo automático de una versión anterior de este script.
USE ASADA;
GO
IF OBJECT_ID('dbo.sp_ConcederAccesoMotorDW', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConcederAccesoMotorDW;
IF OBJECT_ID('dbo.sp_SincronizarAccesoMotorDW', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_SincronizarAccesoMotorDW;
GO

/* ---------------------------------------------------------------------
   Asignación manual (ejecutar como sysadmin; no se crean logins aquí).
   Use el nombre real del login de Windows o de DB_USUARIO:

   USE ASADA_DW;
   CREATE USER [nombre_del_login] FROM LOGIN [nombre_del_login];
   ALTER ROLE Rol_LecturaDW ADD MEMBER [nombre_del_login];  -- solo reportes
   -- ALTER ROLE Rol_CargaDW  ADD MEMBER [nombre_del_login]; -- solo quien ejecute el ETL
   --------------------------------------------------------------------- */
