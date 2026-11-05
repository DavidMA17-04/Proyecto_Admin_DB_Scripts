SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Consultas de demostración — base operacional ASADA

   Solo lectura: vistas y procedimientos ya definidos en los scripts 04–12.
   Ejecutar en SSMS después de la instalación (y opcionalmente 19_datos_demo.sql):

       sqlcmd -S localhost -E -C -f 65001 -i 20_consultas_demostracion.sql

   Ajuste los parámetros de ejemplo (@tipo_abonado, @id_abonado) según sus datos.
   --------------------------------------------------------------------- */
USE ASADA;
GO

   --Abonados y conexiones
select top (20)
    vw_Abonados.tipo_abonado,
    vw_Abonados.id_abonado,
    vw_Abonados.identificacion,
    vw_Abonados.nombre_completo,
    vw_Abonados.telefono,
    vw_Abonados.activo
from dbo.vw_Abonados
order by vw_Abonados.nombre_completo;
GO

exec dbo.sp_ConsultarAbonado;
GO

   --Sustituya tipo e id si desea filtrar una conexión concreta
declare @tipo_abonado varchar(10) = 'FISICO';
declare @id_abonado int = 1;
exec dbo.sp_ConsultarConexionesPorAbonado
    @tipo_abonado = @tipo_abonado,
    @id_abonado   = @id_abonado;
GO

exec dbo.sp_ConsultarMedidores @estado = 'Activo';
GO

   --Lecturas, facturación y consumo
select top (20)
    vw_MedidoresParaLectura.id_medidor,
    vw_MedidoresParaLectura.numero_serie,
    vw_MedidoresParaLectura.id_conexion,
    vw_MedidoresParaLectura.abonado,
    vw_MedidoresParaLectura.ultima_lectura
from dbo.vw_MedidoresParaLectura
order by vw_MedidoresParaLectura.numero_serie;
GO

select top (20)
    vw_MedidorNoLeido.id_medidor,
    vw_MedidorNoLeido.numero_serie,
    vw_MedidorNoLeido.id_conexion,
    vw_MedidorNoLeido.ubicacion
from dbo.vw_MedidorNoLeido;
GO

exec dbo.sp_HistorialConsumo;
GO

select top (20)
    vw_SaldoFactura.id_factura,
    vw_SaldoFactura.id_conexion,
    vw_SaldoFactura.monto_total,
    vw_SaldoFactura.recargos,
    vw_SaldoFactura.pagado,
    vw_SaldoFactura.saldo,
    vw_SaldoFactura.estado
from dbo.vw_SaldoFactura
where vw_SaldoFactura.saldo > 0
order by vw_SaldoFactura.saldo desc;
GO

exec dbo.sp_ConsultarFacturas @estado = 'Pendiente';
GO

select top (20)
    vw_ResumenConsumoMensual.periodo,
    vw_ResumenConsumoMensual.id_conexion,
    vw_ResumenConsumoMensual.abonado,
    vw_ResumenConsumoMensual.consumo_m3
from dbo.vw_ResumenConsumoMensual
order by vw_ResumenConsumoMensual.periodo desc;
GO

   --Pagos, cartera y morosidad
select
    vw_ResumenCartera.fecha_corte,
    vw_ResumenCartera.total_por_cobrar,
    vw_ResumenCartera.total_vencido,
    vw_ResumenCartera.facturas_pendientes,
    vw_ResumenCartera.conexiones_morosas,
    vw_ResumenCartera.recaudado_mes
from dbo.vw_ResumenCartera;
GO

select top (20)
    vw_FacturasPendientes.id_factura,
    vw_FacturasPendientes.nombre_completo,
    vw_FacturasPendientes.saldo,
    vw_FacturasPendientes.dias_atraso
from dbo.vw_FacturasPendientes
order by vw_FacturasPendientes.dias_atraso desc;
GO

exec dbo.sp_GenerarReporteMorosidad @dias_minimos_atraso = 1;
GO

select top (20)
    vw_PagosPorMetodo.nombre_metodo,
    vw_PagosPorMetodo.cantidad_pagos,
    vw_PagosPorMetodo.total_recaudado
from dbo.vw_PagosPorMetodo;
GO

exec dbo.sp_ConsultarHistorialPagos;
GO

declare @tipo_cuenta varchar(10) = 'FISICO';
declare @id_cuenta int = 1;
exec dbo.sp_EstadoCuentaAbonado
    @tipo_abonado = @tipo_cuenta,
    @id_abonado   = @id_cuenta;
GO

select top (20)
    vw_RecargosPendientes.id_recargo,
    vw_RecargosPendientes.id_factura,
    vw_RecargosPendientes.monto_recargo,
    vw_RecargosPendientes.abonado
from dbo.vw_RecargosPendientes;
GO

select
    vw_ParametrosMora.nombre,
    vw_ParametrosMora.valor,
    vw_ParametrosMora.descripcion
from dbo.vw_ParametrosMora;
GO

select
    vw_TramosMora.dias_desde,
    vw_TramosMora.dias_hasta,
    vw_TramosMora.porcentaje,
    vw_TramosMora.activo
from dbo.vw_TramosMora
where vw_TramosMora.activo = 1;
GO

   --Simulación de suspensiones (no cambia datos)
exec dbo.sp_SuspenderConexionesMorosas @solo_simular = 1;
GO

   --Incidencias y mantenimiento
select top (20)
    vw_IncidentesAbiertos.id_incidencia,
    vw_IncidentesAbiertos.tipo,
    vw_IncidentesAbiertos.prioridad,
    vw_IncidentesAbiertos.estado,
    vw_IncidentesAbiertos.horas_abierta
from dbo.vw_IncidentesAbiertos
order by vw_IncidentesAbiertos.fecha_incidente desc;
GO

exec dbo.sp_ConsultarIncidencias @estado = 'Abierta';
GO

declare @id_incidencia int = 1;
exec dbo.sp_ConsultarHistorialIncidencia @id_incidencia = @id_incidencia;
GO

select top (20)
    vw_MantenimientosPendientes.id_mantenimiento,
    vw_MantenimientosPendientes.tipo_trabajo,
    vw_MantenimientosPendientes.responsable,
    vw_MantenimientosPendientes.estado
from dbo.vw_MantenimientosPendientes;
GO

exec dbo.sp_ConsultarMantenimientos;
GO

exec dbo.sp_ConsultarEmpleados @activo = 1;
GO

   --Alertas de consumo
select top (20)
    vw_AlertasActivas.id_alerta,
    vw_AlertasActivas.nivel,
    vw_AlertasActivas.medidor,
    vw_AlertasActivas.porcentaje_variacion
from dbo.vw_AlertasActivas;
GO

exec dbo.sp_ConsultarAlertasConsumo @estado = 'Abierta';
GO

   --Seguridad, usuarios y bitácora
select top (30)
    vw_BitacoraReciente.fecha_registro,
    vw_BitacoraReciente.usuario,
    vw_BitacoraReciente.accion,
    vw_BitacoraReciente.tabla_afectada,
    vw_BitacoraReciente.descripcion
from dbo.vw_BitacoraReciente
order by vw_BitacoraReciente.fecha_registro desc;
GO

exec dbo.sp_ConsultarBitacora;
GO

exec dbo.sp_ConsultarRoles;
GO

exec dbo.sp_ConsultarPermisos;
GO

select top (20)
    vw_UsuariosActivos.nombre_usuario,
    vw_UsuariosActivos.nombre_rol,
    vw_UsuariosActivos.empleado,
    vw_UsuariosActivos.fecha_ultimo_acceso
from dbo.vw_UsuariosActivos;
GO

   --Catálogos
exec dbo.sp_ConsultarTarifas @solo_activas = 1;
GO

exec dbo.sp_ConsultarTiposIncidencia;
GO

exec dbo.sp_ConsultarMetodosPago;
GO

select
    vw_TarifasActivas.id_tarifa,
    vw_TarifasActivas.tipo_tarifa,
    vw_TarifasActivas.monto_fijo,
    vw_TarifasActivas.monto_por_m3
from dbo.vw_TarifasActivas;
GO

   --Políticas de respaldo (lectura directa con relación)
select
    Politica_Respaldo.id_politica,
    Politica_Respaldo.nombre_politica,
    Tipo_Respaldo.nombre_respaldo,
    Politica_Respaldo.frecuencia,
    Politica_Respaldo.activo
from dbo.Politica_Respaldo
inner join dbo.Tipo_Respaldo
    on Tipo_Respaldo.id_tipo_respaldo = Politica_Respaldo.id_tipo_respaldo
where Politica_Respaldo.activo = 1;
GO

exec dbo.sp_ConsultarHistorialRespaldos;
GO

   --Control del Data Warehouse (tabla operacional Control_ETL)
select
    vw_UltimaCargaPorTabla.nombre_tabla_destino,
    vw_UltimaCargaPorTabla.fecha_proceso,
    vw_UltimaCargaPorTabla.filas_procesadas,
    vw_UltimaCargaPorTabla.estado
from dbo.vw_UltimaCargaPorTabla
order by vw_UltimaCargaPorTabla.nombre_tabla_destino;
GO

select
    vw_CargasFallidas.id_proceso_etl,
    vw_CargasFallidas.nombre_tabla_destino,
    vw_CargasFallidas.fecha_proceso,
    vw_CargasFallidas.mensaje_error
from dbo.vw_CargasFallidas;
GO

exec dbo.sp_ConsultarControlETL;
GO

PRINT 'Consultas de demostración ASADA finalizadas.';
GO
