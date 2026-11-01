/* ---------------------------------------------------------------------
   Ejecuta todos los scripts en orden.
   --------------------------------------------------------------------- */
:on error exit
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

:r 00_crear_bases.sql
:r 01_tablas.sql
:r 02_indices.sql
:r 03_funciones.sql
:r 04_vistas.sql
:r 05_procedimientos_abonados_conexiones.sql
:r 06_procedimientos_lecturas_facturacion.sql
:r 07_procedimientos_pagos_mora.sql
:r 08_procedimientos_incidencias_mantenimiento.sql
:r 09_procedimientos_seguridad_bitacora.sql
:r 10_procedimientos_catalogos.sql
:r 11_procedimientos_consumo_anomalo.sql
:r 12_procedimientos_respaldos.sql
:r 13_data_warehouse.sql
:r 14_triggers.sql
:r 15_administracion_y_roles_bd.sql
:r 15_acceso_dw.sql
:r 16_datos_iniciales.sql
:r 18_pruebas.sql

PRINT 'Instalación terminada. Para los jobs ejecute 17_jobs_sql_agent.sql (requiere SQL Server Agent).';
