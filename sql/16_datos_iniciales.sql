SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Script 16: Datos iniciales (catálogos, roles, permisos, políticas)
   Antes de ejecutar, revise la ruta de respaldos (@ruta_respaldos):
   debe existir y la cuenta de servicio de SQL Server debe poder escribir en ella.
   ===================================================================== */
USE ASADA;
GO
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   Tarifas (montos de referencia en colones; ajustar a los aprobados por la ARESEP)
   --------------------------------------------------------------------- */
INSERT INTO dbo.Tipo_Tarifa (nombre_tarifa) VALUES
    ('Residencial'), ('Comercial'), ('Institucional'), ('Preferencial');

INSERT INTO dbo.Tarifa (id_tipo_tarifa, monto_fijo, monto_por_m3)
SELECT id_tipo_tarifa,
       CASE nombre_tarifa WHEN 'Residencial' THEN 3500 WHEN 'Comercial' THEN 6000 WHEN 'Institucional' THEN 5000 ELSE 2500 END,
       CASE nombre_tarifa WHEN 'Residencial' THEN 460  WHEN 'Comercial' THEN 780  WHEN 'Institucional' THEN 600  ELSE 350  END
FROM dbo.Tipo_Tarifa;
GO

/* ---------------------------------------------------------------------
   Catálogos
   --------------------------------------------------------------------- */
INSERT INTO dbo.Metodo_Pago (nombre_metodo) VALUES
    ('Efectivo'), ('Transferencia bancaria'), ('Tarjeta'), ('SINPE Móvil');

INSERT INTO dbo.Tipo_Incidencia (nombre_incidencia) VALUES
    ('Fuga'), ('Medidor dañado'), ('Baja presión'), ('Sin servicio'), ('Tubería rota'), ('Agua turbia'), ('Reclamo de cobro');

INSERT INTO dbo.Tipo_Trabajo (nombre_trabajo) VALUES
    ('Reparación'), ('Preventivo'), ('Instalación'), ('Cambio medidor'), ('Corte'), ('Reconexión');

INSERT INTO dbo.Nivel_alerta_Consumo (nombre_nivel) VALUES ('Bajo'), ('Medio'), ('Alto');

INSERT INTO dbo.Regla_consumo (id_nivel_alerta, nombre_regla, porcentaje_variacion, meses_promedio, consumo_minimo, descripcion)
SELECT n.id_nivel_alerta, r.nombre, r.porcentaje, 3, r.minimo, r.descripcion
FROM (VALUES
    ('Bajo',  'Aumento moderado', 50.00,  10.00, 'Consumo 50 % mayor al promedio de los últimos 3 meses.'),
    ('Medio', 'Aumento alto',     100.00, 10.00, 'Consumo que duplica el promedio de los últimos 3 meses.'),
    ('Alto',  'Posible fuga',     200.00, 15.00, 'Consumo que triplica el promedio; se recomienda inspección.')
) r(nivel, nombre, porcentaje, minimo, descripcion)
JOIN dbo.Nivel_alerta_Consumo n ON n.nombre_nivel = r.nivel;
GO

/* ---------------------------------------------------------------------
   Respaldos
   --------------------------------------------------------------------- */
INSERT INTO dbo.Tipo_Respaldo (nombre_respaldo) VALUES ('Completo'), ('Diferencial'), ('Log');
GO

DECLARE @ruta_respaldos varchar(300) = 'C:\Respaldos\ASADA\';   -- <== AJUSTAR

INSERT INTO dbo.Politica_Respaldo (id_tipo_respaldo, nombre_politica, frecuencia, hora_ejecucion, retencion_dias, ruta_destino)
SELECT t.id_tipo_respaldo, p.nombre, p.frecuencia, p.hora, p.retencion, @ruta_respaldos
FROM (VALUES
    ('Completo',    'Respaldo completo semanal',        'Semanal (domingo)',          '01:00', 30),
    ('Diferencial', 'Respaldo diferencial diario',      'Diario (lunes a sábado)',    '01:00', 14),
    ('Log',         'Respaldo del log cada 15 minutos', 'Cada 15 minutos',            '00:00', 7)
) p(tipo, nombre, frecuencia, hora, retencion)
JOIN dbo.Tipo_Respaldo t ON t.nombre_respaldo = p.tipo;
GO

/* ---------------------------------------------------------------------
   Roles, módulos y permisos de la aplicación (sección 7, matriz de acceso)
   El Abonado no tiene credenciales, por eso no tiene rol.
   --------------------------------------------------------------------- */
INSERT INTO dbo.Rol (nombre_rol) VALUES
    ('Junta Directiva'), ('Administrador del Sistema'), ('Fontanero'), ('Administrador de BD');

INSERT INTO dbo.Modulo (nombre_modulo) VALUES
    ('Usuarios y conexiones'),
    ('Lecturas y facturación'),
    ('Pagos y morosidad'),
    ('Mantenimientos e incidentes'),
    ('Seguridad y auditoría'),
    ('Administración de BD y Data Warehouse');

INSERT INTO dbo.Permiso (id_modulo, nombre_permiso)
SELECT m.id_modulo, p.permiso
FROM (VALUES
    ('Usuarios y conexiones',                 'Consultar abonados y conexiones'),
    ('Usuarios y conexiones',                 'Gestionar abonados y conexiones'),
    ('Lecturas y facturación',                'Consultar lecturas y facturas'),
    ('Lecturas y facturación',                'Gestionar facturación'),
    ('Lecturas y facturación',                'Registrar lectura'),
    ('Pagos y morosidad',                     'Consultar pagos y morosidad'),
    ('Pagos y morosidad',                     'Gestionar pagos y morosidad'),
    ('Mantenimientos e incidentes',           'Consultar mantenimientos e incidencias'),
    ('Mantenimientos e incidentes',           'Gestionar mantenimientos e incidencias'),
    ('Mantenimientos e incidentes',           'Registrar incidencia'),
    ('Mantenimientos e incidentes',           'Ejecutar mantenimiento'),
    ('Seguridad y auditoría',                 'Consultar bitácora'),
    ('Seguridad y auditoría',                 'Gestionar usuarios, roles y permisos'),
    ('Administración de BD y Data Warehouse', 'Consultar reportes y Data Warehouse'),
    ('Administración de BD y Data Warehouse', 'Ejecutar respaldos y restauraciones'),
    ('Administración de BD y Data Warehouse', 'Ejecutar ETL'),
    ('Administración de BD y Data Warehouse', 'Mantenimiento de BD')
) p(modulo, permiso)
JOIN dbo.Modulo m ON m.nombre_modulo = p.modulo;

INSERT INTO dbo.Rol_permiso (id_rol, id_permiso)
SELECT r.id_rol, p.id_permiso
FROM (VALUES
    -- Junta Directiva: solo consulta
    ('Junta Directiva', 'Consultar abonados y conexiones'),
    ('Junta Directiva', 'Consultar lecturas y facturas'),
    ('Junta Directiva', 'Consultar pagos y morosidad'),
    ('Junta Directiva', 'Consultar mantenimientos e incidencias'),
    ('Junta Directiva', 'Consultar bitácora'),
    ('Junta Directiva', 'Consultar reportes y Data Warehouse'),
    -- Fontanero: lecturas, incidencias y mantenimientos asignados
    ('Fontanero', 'Registrar lectura'),
    ('Fontanero', 'Registrar incidencia'),
    ('Fontanero', 'Ejecutar mantenimiento'),
    ('Fontanero', 'Consultar mantenimientos e incidencias'),
    -- Administrador de BD: módulo técnico completo
    ('Administrador de BD', 'Consultar reportes y Data Warehouse'),
    ('Administrador de BD', 'Ejecutar respaldos y restauraciones'),
    ('Administrador de BD', 'Ejecutar ETL'),
    ('Administrador de BD', 'Mantenimiento de BD')
) x(rol, permiso)
JOIN dbo.Rol r     ON r.nombre_rol = x.rol
JOIN dbo.Permiso p ON p.nombre_permiso = x.permiso;

-- Administrador del Sistema: acceso total a los módulos funcionales (1 a 5).
INSERT INTO dbo.Rol_permiso (id_rol, id_permiso)
SELECT r.id_rol, p.id_permiso
FROM dbo.Rol r
CROSS JOIN dbo.Permiso p
JOIN dbo.Modulo m ON m.id_modulo = p.id_modulo
WHERE r.nombre_rol = 'Administrador del Sistema'
  AND m.nombre_modulo <> 'Administración de BD y Data Warehouse';
GO

/* ---------------------------------------------------------------------
   Usuarios iniciales. CAMBIAR LAS CONTRASEÑAS después del primer ingreso
   (sp_CambiarContrasenaUsuario).
   --------------------------------------------------------------------- */
DECLARE @id_empleado int, @id_rol int;

EXEC dbo.sp_AgregarEmpleado
    @cedula = '100000001', @nombre_empleado = 'Administrador', @apellido1_empleado = 'ASADA',
    @puesto = 'Administrador', @id_empleado = @id_empleado OUTPUT;
SELECT @id_rol = id_rol FROM dbo.Rol WHERE nombre_rol = 'Administrador del Sistema';
EXEC dbo.sp_CrearUsuarioSistema @id_empleado = @id_empleado, @id_rol = @id_rol,
    @nombre_usuario = 'admin', @contrasena = N'Asada#2026';

EXEC dbo.sp_AgregarEmpleado
    @cedula = '100000002', @nombre_empleado = 'Administrador', @apellido1_empleado = 'BD',
    @puesto = 'DBA', @id_empleado = @id_empleado OUTPUT;
SELECT @id_rol = id_rol FROM dbo.Rol WHERE nombre_rol = 'Administrador de BD';
EXEC dbo.sp_CrearUsuarioSistema @id_empleado = @id_empleado, @id_rol = @id_rol,
    @nombre_usuario = 'dba', @contrasena = N'AsadaDBA#2026';
GO

PRINT 'Datos iniciales cargados. Usuarios: admin / Asada#2026 y dba / AsadaDBA#2026 (cámbielas).';
GO
