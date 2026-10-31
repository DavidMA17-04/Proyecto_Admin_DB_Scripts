SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Script 01: Tablas de la base transaccional ASADA
   --------------------------------------------------------------------- */
USE ASADA;
GO

   --Seguridad: empleados, roles, permisos, usuarios y bitácora
CREATE TABLE dbo.Empleado (
    id_empleado         int IDENTITY(1,1) NOT NULL,
    cedula              varchar(20)  NOT NULL,
    nombre_empleado     varchar(20)  NOT NULL,
    apellido1_empleado  varchar(20)  NOT NULL,
    apellido2_empleado  varchar(20)  NULL,
    puesto              varchar(20)  NOT NULL,
    telefono            varchar(15)  NULL,
    fecha_contratacion  datetime     NOT NULL CONSTRAINT DF_Empleado_FechaContratacion DEFAULT (GETDATE()),
    activo              bit          NOT NULL CONSTRAINT DF_Empleado_Activo DEFAULT (1),
    CONSTRAINT PK_Empleado PRIMARY KEY (id_empleado)
) ON Seguridad;
GO

CREATE TABLE dbo.Rol (
    id_rol      int IDENTITY(1,1) NOT NULL,
    nombre_rol  varchar(25) NOT NULL,
    CONSTRAINT PK_Rol PRIMARY KEY (id_rol)
) ON Seguridad;
GO

CREATE TABLE dbo.Modulo (
    id_modulo      int IDENTITY(1,1) NOT NULL,
    nombre_modulo  varchar(50) NOT NULL,
    CONSTRAINT PK_Modulo PRIMARY KEY (id_modulo)
) ON Seguridad;
GO

CREATE TABLE dbo.Permiso (
    id_permiso      int IDENTITY(1,1) NOT NULL,
    id_modulo       int         NOT NULL,
    nombre_permiso  varchar(50) NOT NULL,
    CONSTRAINT PK_Permiso PRIMARY KEY (id_permiso),
    CONSTRAINT FK_Permiso_Modulo FOREIGN KEY (id_modulo) REFERENCES dbo.Modulo (id_modulo)
) ON Seguridad;
GO

CREATE TABLE dbo.Rol_permiso (
    id_rol_permiso  int IDENTITY(1,1) NOT NULL,
    id_rol          int NOT NULL,
    id_permiso      int NOT NULL,
    CONSTRAINT PK_Rol_permiso PRIMARY KEY (id_rol_permiso),
    CONSTRAINT FK_RolPermiso_Rol     FOREIGN KEY (id_rol)     REFERENCES dbo.Rol (id_rol),
    CONSTRAINT FK_RolPermiso_Permiso FOREIGN KEY (id_permiso) REFERENCES dbo.Permiso (id_permiso)
) ON Seguridad;
GO

CREATE TABLE dbo.Usuario_Sistema (
    id_usuario_sistema   int IDENTITY(1,1) NOT NULL,
    id_empleado          int          NOT NULL,
    id_rol               int          NOT NULL,
    nombre_usuario       varchar(50)  NOT NULL,
    -- Se guarda el hash SHA2-256 en hexadecimal
    contrasena_usuario   varchar(64)  NOT NULL,
    activo               bit          NOT NULL CONSTRAINT DF_UsuarioSistema_Activo DEFAULT (1),
    intentos_fallidos    int          NOT NULL CONSTRAINT DF_UsuarioSistema_Intentos DEFAULT (0),   
    fecha_ultimo_acceso  datetime     NULL,                                                         
    CONSTRAINT PK_Usuario_Sistema PRIMARY KEY (id_usuario_sistema),
    CONSTRAINT FK_UsuarioSistema_Empleado FOREIGN KEY (id_empleado) REFERENCES dbo.Empleado (id_empleado),
    CONSTRAINT FK_UsuarioSistema_Rol      FOREIGN KEY (id_rol)      REFERENCES dbo.Rol (id_rol),
    CONSTRAINT CK_UsuarioSistema_Intentos CHECK (intentos_fallidos >= 0)
) ON Seguridad;
GO

CREATE TABLE dbo.Bitacora (
    id_bitacora         int IDENTITY(1,1) NOT NULL,
    -- NULL cuando la acción la ejecuta un proceso automático (job, ETL) sin sesión de usuario
    id_usuario_sistema  int          NULL,
    fecha_registro      datetime     NOT NULL CONSTRAINT DF_Bitacora_Fecha DEFAULT (GETDATE()),
    accion              varchar(15)  NOT NULL,
    tabla_afectada      varchar(50)  NULL,                                                          
    descripcion         varchar(max) NULL,
    CONSTRAINT PK_Bitacora PRIMARY KEY (id_bitacora),
    CONSTRAINT FK_Bitacora_UsuarioSistema FOREIGN KEY (id_usuario_sistema) REFERENCES dbo.Usuario_Sistema (id_usuario_sistema)
) ON Auditoria;
GO

   --Tarifas
CREATE TABLE dbo.Tipo_Tarifa (
    id_tipo_tarifa  int IDENTITY(1,1) NOT NULL,
    nombre_tarifa   varchar(15) NOT NULL,
    activo          bit NOT NULL CONSTRAINT DF_TipoTarifa_Activo DEFAULT (1),                       
    CONSTRAINT PK_Tipo_Tarifa PRIMARY KEY (id_tipo_tarifa)
) ON Facturacion;
GO

CREATE TABLE dbo.Tarifa (
    id_tarifa       int IDENTITY(1,1) NOT NULL,
    id_tipo_tarifa  int           NOT NULL,
    monto_fijo      decimal(10,2) NOT NULL,
    monto_por_m3    decimal(10,2) NOT NULL,
    activo          bit           NOT NULL CONSTRAINT DF_Tarifa_Activo DEFAULT (1),                 
    CONSTRAINT PK_Tarifa PRIMARY KEY (id_tarifa),
    CONSTRAINT FK_Tarifa_TipoTarifa FOREIGN KEY (id_tipo_tarifa) REFERENCES dbo.Tipo_Tarifa (id_tipo_tarifa),
    CONSTRAINT CK_Tarifa_MontosPositivos CHECK (monto_fijo > 0 AND monto_por_m3 > 0)
) ON Facturacion;
GO

--Tabla usada por sp_ConsultarHistorialTarifa y fn_ObtenerTarifaVigente
CREATE TABLE dbo.Historial_Tarifa (
    id_historial_tarifa    int IDENTITY(1,1) NOT NULL,
    id_tarifa              int           NOT NULL,
    monto_fijo_anterior    decimal(10,2) NOT NULL,
    monto_fijo_nuevo       decimal(10,2) NOT NULL,
    monto_por_m3_anterior  decimal(10,2) NOT NULL,
    monto_por_m3_nuevo     decimal(10,2) NOT NULL,
    fecha_cambio           datetime      NOT NULL CONSTRAINT DF_HistorialTarifa_Fecha DEFAULT (GETDATE()),
    id_usuario_sistema     int           NULL,
    CONSTRAINT PK_Historial_Tarifa PRIMARY KEY (id_historial_tarifa),
    CONSTRAINT FK_HistorialTarifa_Tarifa  FOREIGN KEY (id_tarifa) REFERENCES dbo.Tarifa (id_tarifa),
    CONSTRAINT FK_HistorialTarifa_Usuario FOREIGN KEY (id_usuario_sistema) REFERENCES dbo.Usuario_Sistema (id_usuario_sistema)
) ON Auditoria;
GO

  -- Abonados, conexiones y medidores
CREATE TABLE dbo.Abonado_Fisico (
    id_abonado_fisico    int IDENTITY(1,1) NOT NULL,
    tipo_identificacion  varchar(20)  NOT NULL,
    numero_identidad     varchar(20)  NOT NULL,
    nombre               varchar(50)  NOT NULL,
    apellido1            varchar(50)  NOT NULL,
    apellido2            varchar(50)  NULL,
    fecha_nacimiento     date         NULL,
    direccion            varchar(200) NOT NULL,
    telefono             varchar(20)  NULL,
    correo_electronico   varchar(100) NULL,
    fecha_registro       datetime     NOT NULL CONSTRAINT DF_AbonadoFisico_Fecha DEFAULT (GETDATE()),
    activo               bit          NOT NULL CONSTRAINT DF_AbonadoFisico_Activo DEFAULT (1),      
    CONSTRAINT PK_Abonado_Fisico PRIMARY KEY (id_abonado_fisico),
    CONSTRAINT CK_AbonadoFisico_TipoId CHECK (tipo_identificacion IN ('FISICA', 'DIMEX', 'NITE', 'PASAPORTE'))
) ON Abonados;
GO

CREATE TABLE dbo.Abonado_Juridico (
    id_abonado_juridico      int IDENTITY(1,1) NOT NULL,
    cedula_juridica          varchar(50)  NOT NULL,
    razon_social             varchar(50)  NOT NULL,
    cedula_representante     varchar(20)  NOT NULL,
    nombre_representante     varchar(50)  NOT NULL,
    apellido1_representante  varchar(50)  NOT NULL,
    apellido2_representante  varchar(50)  NULL,
    direccion                varchar(200) NOT NULL,
    telefono                 varchar(20)  NULL,
    correo_electronico       varchar(100) NULL,
    fecha_registro           datetime     NOT NULL CONSTRAINT DF_AbonadoJuridico_Fecha DEFAULT (GETDATE()),
    activo                   bit          NOT NULL CONSTRAINT DF_AbonadoJuridico_Activo DEFAULT (1), 
    CONSTRAINT PK_Abonado_Juridico PRIMARY KEY (id_abonado_juridico)
) ON Abonados;
GO

CREATE TABLE dbo.Conexion (
    id_conexion          int IDENTITY(1,1) NOT NULL,
    id_abonado_fisico    int          NULL,
    id_abonado_juridico  int          NULL,
    id_tarifa            int          NOT NULL,
    ubicacion            varchar(50)  NOT NULL,
    estado               varchar(25)  NOT NULL CONSTRAINT DF_Conexion_Estado DEFAULT ('Activa'),
    fecha_conexion       datetime     NOT NULL CONSTRAINT DF_Conexion_Fecha DEFAULT (GETDATE()),
    fecha_modificacion   datetime     NULL,
    CONSTRAINT PK_Conexion PRIMARY KEY (id_conexion),
    CONSTRAINT FK_Conexion_AbonadoFisico   FOREIGN KEY (id_abonado_fisico)   REFERENCES dbo.Abonado_Fisico (id_abonado_fisico),
    CONSTRAINT FK_Conexion_AbonadoJuridico FOREIGN KEY (id_abonado_juridico) REFERENCES dbo.Abonado_Juridico (id_abonado_juridico),
    CONSTRAINT FK_Conexion_Tarifa          FOREIGN KEY (id_tarifa)           REFERENCES dbo.Tarifa (id_tarifa),
    -- Regla de negocio Conexión-Abonado: exactamente un titular, físico o jurídico, nunca ambos ni ninguno
    CONSTRAINT ck_AbonadoORjuridico CHECK (
        (id_abonado_fisico IS NOT NULL AND id_abonado_juridico IS NULL) OR
        (id_abonado_fisico IS NULL AND id_abonado_juridico IS NOT NULL)
    ),
    CONSTRAINT CK_Conexion_EstadoValido CHECK (estado IN ('Activa', 'Suspendida', 'Cortada', 'Inactiva'))
) ON Abonados;
GO

CREATE TABLE dbo.Medidor (
    id_medidor            int IDENTITY(1,1) NOT NULL,
    id_conexion           int           NOT NULL,
    numero_serie          varchar(20)   NOT NULL,
    fecha_instalacion     datetime      NOT NULL CONSTRAINT DF_Medidor_Fecha DEFAULT (GETDATE()),
    estado                varchar(10)   NOT NULL CONSTRAINT DF_Medidor_Estado DEFAULT ('Activo'),
    ultima_lectura        decimal(10,2) NULL,                                                       
    fecha_ultima_lectura  datetime      NULL,                                                       
    CONSTRAINT PK_Medidor PRIMARY KEY (id_medidor),
    CONSTRAINT FK_Medidor_Conexion FOREIGN KEY (id_conexion) REFERENCES dbo.Conexion (id_conexion),
    CONSTRAINT CK_Medidor_EstadoValido CHECK (estado IN ('Activo', 'Dañado', 'Sustituido', 'Retirado'))
) ON Abonados;
GO

   --Lecturas, facturación, pagos y mora
CREATE TABLE dbo.Lectura (
    id_lectura            int IDENTITY(1,1) NOT NULL,
    id_medidor            int           NOT NULL,
    fecha_lectura_actual  datetime      NOT NULL CONSTRAINT DF_Lectura_Fecha DEFAULT (GETDATE()),
    lectura_anterior      decimal(10,2) NOT NULL,
    lectura_actual        decimal(10,2) NOT NULL,
    -- Columna calculada: garantiza que el consumo siempre sea lectura_actual - lectura_anterior
    consumo               AS CAST(lectura_actual - lectura_anterior AS decimal(10,2)) PERSISTED,
    CONSTRAINT PK_Lectura PRIMARY KEY (id_lectura),
    CONSTRAINT FK_Lectura_Medidor FOREIGN KEY (id_medidor) REFERENCES dbo.Medidor (id_medidor),
    CONSTRAINT CK_Lectura_ValorValido CHECK (lectura_anterior >= 0 AND lectura_actual >= lectura_anterior)
) ON Facturacion;
GO

CREATE TABLE dbo.Factura (
    id_factura          int IDENTITY(1,1) NOT NULL,
    id_lectura          int           NOT NULL,
    fecha_emision       datetime      NOT NULL CONSTRAINT DF_Factura_Fecha DEFAULT (GETDATE()),
    fecha_vencimiento   date          NOT NULL,
    monto_consumo       decimal(10,2) NOT NULL,
    monto_fijo          decimal(10,2) NOT NULL,
    monto_total         AS CAST(monto_consumo + monto_fijo AS decimal(10,2)) PERSISTED,
    estado              varchar(10)   NOT NULL CONSTRAINT DF_Factura_Estado DEFAULT ('Pendiente'),
    fecha_modificacion  datetime      NULL,
    CONSTRAINT PK_Factura PRIMARY KEY (id_factura),
    CONSTRAINT FK_Factura_Lectura FOREIGN KEY (id_lectura) REFERENCES dbo.Lectura (id_lectura),
    CONSTRAINT UQ_Factura_Lectura UNIQUE (id_lectura),   -- una lectura origina una sola factura
    CONSTRAINT CK_Factura_EstadoValido CHECK (estado IN ('Pendiente', 'Pagada', 'Vencida')),
    CONSTRAINT CK_Factura_Montos CHECK (monto_consumo >= 0 AND monto_fijo >= 0)
) ON Facturacion;
GO

CREATE TABLE dbo.Recargo_mora (
    id_recargo           int IDENTITY(1,1) NOT NULL,
    id_factura           int           NOT NULL,
    fecha_calculo        datetime      NOT NULL CONSTRAINT DF_RecargoMora_Fecha DEFAULT (GETDATE()),
    porcentaje_aplicado  decimal(5,2)  NOT NULL,
    monto_recargo        decimal(10,2) NOT NULL,                                                    
    estado               varchar(10)   NOT NULL CONSTRAINT DF_RecargoMora_Estado DEFAULT ('Aplicado'), 
    motivo_anulacion     varchar(250)  NULL,                                                        
    anulado_manual       bit           NOT NULL CONSTRAINT DF_RecargoMora_AnuladoManual DEFAULT 0,    
    CONSTRAINT PK_Recargo_mora PRIMARY KEY (id_recargo),
    CONSTRAINT FK_RecargoMora_Factura FOREIGN KEY (id_factura) REFERENCES dbo.Factura (id_factura),
    CONSTRAINT CK_RecargoMora_PorcentajeValido CHECK (porcentaje_aplicado > 0 AND porcentaje_aplicado <= 100),
    CONSTRAINT CK_RecargoMora_Estado CHECK (estado IN ('Aplicado', 'Anulado'))
) ON Facturacion;
GO

CREATE TABLE dbo.Metodo_Pago (
    id_metodo_pago  int IDENTITY(1,1) NOT NULL,
    nombre_metodo   varchar(50) NOT NULL,
    activo          bit NOT NULL CONSTRAINT DF_MetodoPago_Activo DEFAULT (1),                       
    CONSTRAINT PK_Metodo_Pago PRIMARY KEY (id_metodo_pago)
) ON Facturacion;
GO

CREATE TABLE dbo.Pago (
    id_pago           int IDENTITY(1,1) NOT NULL,
    id_factura        int           NOT NULL,
    id_metodo_pago    int           NOT NULL,
    fecha_pago        date          NOT NULL CONSTRAINT DF_Pago_Fecha DEFAULT (CAST(GETDATE() AS date)),
    monto             decimal(10,2) NOT NULL,                                                       
    estado            varchar(10)   NOT NULL CONSTRAINT DF_Pago_Estado DEFAULT ('Aplicado'),        
    motivo_anulacion  varchar(250)  NULL,                                                           
    CONSTRAINT PK_Pago PRIMARY KEY (id_pago),
    CONSTRAINT FK_Pago_Factura    FOREIGN KEY (id_factura)     REFERENCES dbo.Factura (id_factura),
    CONSTRAINT FK_Pago_MetodoPago FOREIGN KEY (id_metodo_pago) REFERENCES dbo.Metodo_Pago (id_metodo_pago),
    CONSTRAINT CK_Pago_MontoPositivo CHECK (monto > 0),
    CONSTRAINT CK_Pago_Estado CHECK (estado IN ('Aplicado', 'Anulado'))
) ON Facturacion;
GO

-- Tramos de mora: el porcentaje de recargo depende de los días de atraso
-- Son configurables para que la ASADA pueda ajustarlos sin tocar código
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

-- Parámetros de morosidad: límites para suspender una conexión y plazo de pago
CREATE TABLE dbo.Parametro_Mora (
    nombre              varchar(50)   NOT NULL,
    valor               decimal(12,2) NOT NULL,
    descripcion         varchar(200)  NULL,
    fecha_modificacion  datetime      NOT NULL CONSTRAINT DF_ParametroMora_Fecha DEFAULT (GETDATE()),
    CONSTRAINT PK_Parametro_Mora PRIMARY KEY (nombre),
    CONSTRAINT CK_ParametroMora_Valor CHECK (valor >= 0)
) ON Administracion;
GO

   --Incidencias y mantenimientos
CREATE TABLE dbo.Tipo_Incidencia (
    id_tipo_incidencia  int IDENTITY(1,1) NOT NULL,
    nombre_incidencia   varchar(20) NOT NULL,
    activo              bit NOT NULL CONSTRAINT DF_TipoIncidencia_Activo DEFAULT (1),              
    CONSTRAINT PK_Tipo_Incidencia PRIMARY KEY (id_tipo_incidencia)
) ON Operaciones;
GO

CREATE TABLE dbo.Incidencia (
    id_incidencia       int IDENTITY(1,1) NOT NULL,
    id_medidor          int          NOT NULL,
    id_tipo_incidencia  int          NOT NULL,
    fecha_incidente     datetime     NOT NULL CONSTRAINT DF_Incidencia_Fecha DEFAULT (GETDATE()),
    descripcion         varchar(100) NOT NULL,
    ubicacion           varchar(20)  NULL,
    estado              varchar(20)  NOT NULL CONSTRAINT DF_Incidencia_Estado DEFAULT ('Abierta'),
    prioridad           varchar(10)  NULL,
    fecha_modificacion  datetime     NULL CONSTRAINT DF_Incidencia_FechaMod DEFAULT (GETDATE()),
    CONSTRAINT PK_Incidencia PRIMARY KEY (id_incidencia),
    CONSTRAINT FK_Incidencia_Medidor        FOREIGN KEY (id_medidor)         REFERENCES dbo.Medidor (id_medidor),
    CONSTRAINT FK_Incidencia_TipoIncidencia FOREIGN KEY (id_tipo_incidencia) REFERENCES dbo.Tipo_Incidencia (id_tipo_incidencia),
    CONSTRAINT CK_Incidencia_EstadoValido CHECK (estado IN ('Abierta', 'En proceso', 'Resuelta')),
    CONSTRAINT CK_Incidencia_Prioridad CHECK (prioridad IN ('Alta', 'Media', 'Baja'))
) ON Operaciones;
GO

CREATE TABLE dbo.Historial_Incidencia (
    id_historial_incidencia  int IDENTITY(1,1) NOT NULL,
    id_incidencia            int          NOT NULL,
    id_empleado              int          NULL,
    estado_anterior          varchar(20)  NULL,
    estado_actual            varchar(20)  NOT NULL,
    fecha_evento             datetime     NOT NULL CONSTRAINT DF_HistorialIncidencia_Fecha DEFAULT (GETDATE()),
    observacion              varchar(max) NULL,
    CONSTRAINT PK_Historial_Incidencia PRIMARY KEY (id_historial_incidencia),
    CONSTRAINT FK_HistorialIncidencia_Incidencia FOREIGN KEY (id_incidencia) REFERENCES dbo.Incidencia (id_incidencia),
    CONSTRAINT FK_HistorialIncidencia_Empleado   FOREIGN KEY (id_empleado)   REFERENCES dbo.Empleado (id_empleado)
) ON Auditoria;
GO

CREATE TABLE dbo.Tipo_Trabajo (
    id_tipo_trabajo  int IDENTITY(1,1) NOT NULL,
    nombre_trabajo   varchar(15) NOT NULL,
    activo           bit NOT NULL CONSTRAINT DF_TipoTrabajo_Activo DEFAULT (1),                     
    CONSTRAINT PK_Tipo_Trabajo PRIMARY KEY (id_tipo_trabajo)
) ON Operaciones;
GO

CREATE TABLE dbo.Mantenimiento (
    id_mantenimiento    int IDENTITY(1,1) NOT NULL,
    id_empleado         int          NOT NULL,
    id_tipo_trabajo     int          NOT NULL,
    id_conexion         int          NOT NULL,
    id_incidencia       int          NULL,   -- NULL cuando es un mantenimiento preventivo programado
    descripcion         varchar(100) NOT NULL,
    fecha_inicio        datetime     NOT NULL CONSTRAINT DF_Mantenimiento_Inicio DEFAULT (GETDATE()),
    fecha_fin           datetime     NULL,
    estado              varchar(20)  NOT NULL CONSTRAINT DF_Mantenimiento_Estado DEFAULT ('Programado'),
    fecha_modificacion  datetime     NULL,
    CONSTRAINT PK_Mantenimiento PRIMARY KEY (id_mantenimiento),
    CONSTRAINT FK_Mantenimiento_Empleado    FOREIGN KEY (id_empleado)     REFERENCES dbo.Empleado (id_empleado),
    CONSTRAINT FK_Mantenimiento_TipoTrabajo FOREIGN KEY (id_tipo_trabajo) REFERENCES dbo.Tipo_Trabajo (id_tipo_trabajo),
    CONSTRAINT FK_Mantenimiento_Conexion    FOREIGN KEY (id_conexion)     REFERENCES dbo.Conexion (id_conexion),
    CONSTRAINT FK_Mantenimiento_Incidencia  FOREIGN KEY (id_incidencia)   REFERENCES dbo.Incidencia (id_incidencia),
    CONSTRAINT CK_Mantenimiento_EstadoValido CHECK (estado IN ('Programado', 'En proceso', 'Finalizado', 'Cancelado')),
    CONSTRAINT CK_Mantenimiento_Fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
) ON Operaciones;
GO

CREATE TABLE dbo.Historial_Mantenimiento (
    id_historial_mantenimiento  int IDENTITY(1,1) NOT NULL,
    id_mantenimiento            int          NOT NULL,
    id_empleado                 int          NULL,
    estado_anterior             varchar(20)  NULL,
    estado_actual               varchar(20)  NOT NULL,
    fecha_evento                datetime     NOT NULL CONSTRAINT DF_HistorialMantenimiento_Fecha DEFAULT (GETDATE()),
    anotacion                   varchar(max) NULL,
    CONSTRAINT PK_Historial_Mantenimiento PRIMARY KEY (id_historial_mantenimiento),
    CONSTRAINT FK_HistorialMantenimiento_Mantenimiento FOREIGN KEY (id_mantenimiento) REFERENCES dbo.Mantenimiento (id_mantenimiento),
    CONSTRAINT FK_HistorialMantenimiento_Empleado      FOREIGN KEY (id_empleado)      REFERENCES dbo.Empleado (id_empleado)
) ON Auditoria;
GO

   --Detección de consumos anómalos (R9)
CREATE TABLE dbo.Nivel_alerta_Consumo (
    id_nivel_alerta  int IDENTITY(1,1) NOT NULL,
    nombre_nivel     varchar(50) NOT NULL,
    CONSTRAINT PK_Nivel_alerta_Consumo PRIMARY KEY (id_nivel_alerta)
) ON Operaciones;
GO

CREATE TABLE dbo.Regla_consumo (
    id_regla_consumo      int IDENTITY(1,1) NOT NULL,
    id_nivel_alerta       int           NOT NULL,
    nombre_regla          varchar(50)   NOT NULL,
    porcentaje_variacion  decimal(5,2)  NOT NULL,
    meses_promedio        int           NOT NULL,
    consumo_minimo        decimal(10,2) NOT NULL CONSTRAINT DF_ReglaConsumo_Minimo DEFAULT (0),
    descripcion           varchar(250)  NULL,
    activo                bit           NOT NULL CONSTRAINT DF_ReglaConsumo_Activo DEFAULT (1),
    fecha_creacion        datetime      NOT NULL CONSTRAINT DF_ReglaConsumo_Fecha DEFAULT (GETDATE()),
    CONSTRAINT PK_Regla_consumo PRIMARY KEY (id_regla_consumo),
    CONSTRAINT FK_ReglaConsumo_Nivel FOREIGN KEY (id_nivel_alerta) REFERENCES dbo.Nivel_alerta_Consumo (id_nivel_alerta),
    CONSTRAINT CK_ReglaConsumo_Parametros CHECK (porcentaje_variacion > 0 AND meses_promedio BETWEEN 1 AND 24 AND consumo_minimo >= 0)
) ON Operaciones;
GO

CREATE TABLE dbo.Alerta_Consumo (
    id_alerta             int IDENTITY(1,1) NOT NULL,
    id_regla_consumo      int           NOT NULL,
    id_lectura            int           NOT NULL,
    id_incidencia         int           NULL,                                                       
    consumo_promedio      decimal(10,2) NOT NULL,
    consumo_actual        decimal(10,2) NOT NULL,
    porcentaje_variacion  decimal(7,2)  NULL,
    estado                varchar(10)   NOT NULL CONSTRAINT DF_AlertaConsumo_Estado DEFAULT ('Abierta'),
    fecha_deteccion       date          NOT NULL CONSTRAINT DF_AlertaConsumo_Fecha DEFAULT (CAST(GETDATE() AS date)),
    observacion           varchar(max)  NULL,
    fecha_resolucion      date          NULL,
    CONSTRAINT PK_Alerta_Consumo PRIMARY KEY (id_alerta),
    CONSTRAINT FK_AlertaConsumo_Regla      FOREIGN KEY (id_regla_consumo) REFERENCES dbo.Regla_consumo (id_regla_consumo),
    CONSTRAINT FK_AlertaConsumo_Lectura    FOREIGN KEY (id_lectura)       REFERENCES dbo.Lectura (id_lectura),
    CONSTRAINT FK_AlertaConsumo_Incidencia FOREIGN KEY (id_incidencia)    REFERENCES dbo.Incidencia (id_incidencia),
    CONSTRAINT CK_AlertaConsumo_Estado CHECK (
        (estado = 'Abierta'  AND fecha_resolucion IS NULL) OR
        (estado = 'Resuelta' AND fecha_resolucion IS NOT NULL)
    )
) ON Operaciones;
GO

   --Respaldos y restauraciones 
CREATE TABLE dbo.Tipo_Respaldo (
    id_tipo_respaldo  int IDENTITY(1,1) NOT NULL,
    nombre_respaldo   varchar(15) NOT NULL,
    CONSTRAINT PK_Tipo_Respaldo PRIMARY KEY (id_tipo_respaldo),
    CONSTRAINT CK_TipoRespaldo_Nombre CHECK (nombre_respaldo IN ('Completo', 'Diferencial', 'Log'))
) ON Administracion;
GO

CREATE TABLE dbo.Politica_Respaldo (
    id_politica       int IDENTITY(1,1) NOT NULL,
    id_tipo_respaldo  int          NOT NULL,
    nombre_politica   varchar(100) NOT NULL,
    frecuencia        varchar(50)  NOT NULL,
    hora_ejecucion    time(0)      NOT NULL,
    retencion_dias    int          NOT NULL,
    ruta_destino      varchar(300) NOT NULL,
    activo            bit          NOT NULL CONSTRAINT DF_PoliticaRespaldo_Activo DEFAULT (1),
    fecha_creacion    datetime     NOT NULL CONSTRAINT DF_PoliticaRespaldo_Fecha DEFAULT (GETDATE()),
    CONSTRAINT PK_Politica_Respaldo PRIMARY KEY (id_politica),
    CONSTRAINT FK_PoliticaRespaldo_Tipo FOREIGN KEY (id_tipo_respaldo) REFERENCES dbo.Tipo_Respaldo (id_tipo_respaldo),
    CONSTRAINT CK_PoliticaRespaldo_Retencion CHECK (retencion_dias > 0)
) ON Administracion;
GO

CREATE TABLE dbo.Historial_Respaldo (
    id_respaldo    int IDENTITY(1,1) NOT NULL,
    id_politica    int           NOT NULL,
    fecha_inicio   datetime      NOT NULL,
    fecha_fin      datetime      NULL,
    ruta_archivo   varchar(300)  NOT NULL,
    tamano_bytes   bigint        NULL,
    estado         varchar(20)   NOT NULL,
    mensaje_error  varchar(500)  NULL,
    verificado     bit           NOT NULL CONSTRAINT DF_HistorialRespaldo_Verificado DEFAULT (0),
    CONSTRAINT PK_Historial_Respaldo PRIMARY KEY (id_respaldo),
    CONSTRAINT FK_HistorialRespaldo_Politica FOREIGN KEY (id_politica) REFERENCES dbo.Politica_Respaldo (id_politica),
    CONSTRAINT CK_HistorialRespaldo_Estado CHECK (estado IN ('Exitoso', 'Fallido'))
) ON Administracion;
GO

CREATE TABLE dbo.Historial_Restauracion (
    id_restauracion     int IDENTITY(1,1) NOT NULL,
    id_usuario_sistema  int           NULL,
    fecha_solicitud     datetime      NOT NULL CONSTRAINT DF_HistorialRestauracion_Fecha DEFAULT (GETDATE()),
    punto_recuperacion  datetime      NOT NULL,
    fecha_inicio        datetime      NULL,
    fecha_fin           datetime      NULL,
    estado              varchar(20)   NOT NULL,
    base_destino        varchar(100)  NOT NULL,
    motivo              varchar(250)  NOT NULL,
    observacion         varchar(500)  NULL,
    CONSTRAINT PK_Historial_Restauracion PRIMARY KEY (id_restauracion),
    CONSTRAINT FK_HistorialRestauracion_Usuario FOREIGN KEY (id_usuario_sistema) REFERENCES dbo.Usuario_Sistema (id_usuario_sistema),
    CONSTRAINT CK_HistorialRestauracion_Estado CHECK (estado IN ('Solicitada', 'En proceso', 'Exitosa', 'Fallida'))
) ON Administracion;
GO

   --Control del proceso ETL hacia el Data Warehouse 
CREATE TABLE dbo.Control_ETL (
    id_proceso_etl        int IDENTITY(1,1) NOT NULL,
    nombre_tabla_destino  varchar(50)  NOT NULL,
    fecha_ultima_carga    datetime     NULL,
    fecha_proceso         datetime     NOT NULL CONSTRAINT DF_ControlETL_Fecha DEFAULT (GETDATE()),
    filas_procesadas      int          NOT NULL CONSTRAINT DF_ControlETL_Filas DEFAULT (0),
    estado                varchar(20)  NOT NULL,
    mensaje_error         varchar(500) NULL,
    reintentado           bit          NOT NULL CONSTRAINT DF_ControlETL_Reintentado DEFAULT (0),   
    CONSTRAINT PK_Control_ETL PRIMARY KEY (id_proceso_etl),
    CONSTRAINT CK_ControlETL_Estado CHECK (estado IN ('En proceso', 'Exitoso', 'Fallido'))
) ON Administracion;
GO
