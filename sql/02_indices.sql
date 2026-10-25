SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Script 02: Índices
   Nombres tomados de la sección 12 del documento.
   ===================================================================== */
USE ASADA;
GO

-- 12.1 Abonado: cédula única y búsqueda rápida por identificación
CREATE UNIQUE INDEX IX_Abonado_NumeroIdentidad ON dbo.Abonado_Fisico (numero_identidad);
CREATE UNIQUE INDEX IX_Abonado_CedulaJuridica  ON dbo.Abonado_Juridico (cedula_juridica);
GO

-- 12.2 Conexión: búsqueda de conexiones por abonado (físico y jurídico)
CREATE INDEX IX_Conexion_IdUsuario         ON dbo.Conexion (id_abonado_fisico)   INCLUDE (estado, id_tarifa) WHERE id_abonado_fisico IS NOT NULL;
CREATE INDEX IX_Conexion_IdAbonadoJuridico ON dbo.Conexion (id_abonado_juridico) INCLUDE (estado, id_tarifa) WHERE id_abonado_juridico IS NOT NULL;
GO

-- 12.3 Medidor: número de serie único; como respaldo de sp_MedidorExiste,
-- un índice filtrado impide dos medidores activos en la misma conexión.
CREATE UNIQUE INDEX IX_Medidor_NumeroSerie        ON dbo.Medidor (numero_serie);
CREATE UNIQUE INDEX UX_Medidor_ActivoPorConexion  ON dbo.Medidor (id_conexion) WHERE estado = 'Activo';
GO

-- 12.4 Lectura: consultas históricas por medidor y fecha
CREATE INDEX IX_Lectura_IdMedidor_Fecha ON dbo.Lectura (id_medidor, fecha_lectura_actual DESC) INCLUDE (lectura_actual, consumo);
GO

-- 12.5 Factura: filtros por estado (reportes de morosidad)
CREATE INDEX IX_Factura_Estado ON dbo.Factura (estado, fecha_vencimiento) INCLUDE (monto_total);
GO

-- 12.6 Pago: pagos de una factura
CREATE INDEX IX_Pago_IdFactura ON dbo.Pago (id_factura) INCLUDE (monto, estado);
GO

-- 12.7 Incidencia: reportes por estado y fecha
CREATE INDEX IX_Incidente_Estado_Fecha ON dbo.Incidencia (estado, fecha_incidente);
GO

-- 12.13 / 12.14 Tarifa y tipo de tarifa
CREATE INDEX        IX_Tarifa_IdTipoTarifa ON dbo.Tarifa (id_tipo_tarifa);
CREATE UNIQUE INDEX IX_TipoTarifa_Nombre   ON dbo.Tipo_Tarifa (nombre_tarifa);
GO

-- 12.15 Recargo por mora
CREATE INDEX IX_RecargoMora_IdFactura    ON dbo.Recargo_mora (id_factura) INCLUDE (monto_recargo, estado);
CREATE INDEX IX_RecargoMora_FechaCalculo ON dbo.Recargo_mora (fecha_calculo);
GO

-- 12.19 Mantenimiento
CREATE INDEX IX_Mantenimiento_IdEmpleado ON dbo.Mantenimiento (id_empleado, estado);
CREATE INDEX IX_Mantenimiento_IdConexion ON dbo.Mantenimiento (id_conexion);
GO

-- 12.24 a 12.28 Seguridad
CREATE UNIQUE INDEX IX_UsuarioSistema_NombreUsuario ON dbo.Usuario_Sistema (nombre_usuario);
CREATE UNIQUE INDEX IX_Rol_Nombre                   ON dbo.Rol (nombre_rol);
CREATE INDEX        IX_Permiso_IdModulo             ON dbo.Permiso (id_modulo);
CREATE UNIQUE INDEX IX_RolPermiso_RolPermiso_Unico  ON dbo.Rol_permiso (id_rol, id_permiso);
CREATE UNIQUE INDEX IX_Modulo_Nombre                ON dbo.Modulo (nombre_modulo);
GO

-- Empleado: cédula única (la usa sp_ModificarEmpleado para evitar duplicados)
CREATE UNIQUE INDEX IX_Empleado_Cedula ON dbo.Empleado (cedula);
GO

-- Bitácora: consultas por fecha, usuario y tabla
CREATE INDEX IX_Bitacora_Fecha ON dbo.Bitacora (fecha_registro DESC) INCLUDE (id_usuario_sistema, accion, tabla_afectada);
GO

-- 12.31 Control ETL: monitoreo de cargas pendientes o fallidas
CREATE INDEX IX_ControlETL_Estado ON dbo.Control_ETL (estado, nombre_tabla_destino, fecha_proceso DESC);
GO

-- Respaldos: armar la cadena de restauración por fecha
CREATE INDEX IX_HistorialRespaldo_Fecha ON dbo.Historial_Respaldo (fecha_inicio) INCLUDE (id_politica, estado, ruta_archivo);
GO
