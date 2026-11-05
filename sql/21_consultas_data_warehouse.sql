SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Consultas de demostración — Data Warehouse ASADA_DW

   Réplica en SSMS de los reportes GET /dw/ del backend (administracion.js)
   y de validación/conciliación ETL. Requiere carga previa del DW
   (sp_EjecutarCargaDW o 19_datos_demo.sql).

       sqlcmd -S localhost -E -C -f 65001 -i 21_consultas_data_warehouse.sql

   @anio y @fecha_corte en null muestran todo el histórico cargado.
   --------------------------------------------------------------------- */
USE ASADA_DW;
GO

   --Dimensiones (conteo y muestra)
select count(*) as filas from dbo.DIM_TIEMPO;
select count(*) as filas from dbo.DIM_ABONADO;
select count(*) as filas from dbo.DIM_CONEXION;
select count(*) as filas from dbo.DIM_TARIFA;
select count(*) as filas from dbo.DIM_EMPLEADO;
select count(*) as filas from dbo.DIM_TIPO_TRABAJO;
select count(*) as filas from dbo.DIM_TIPO_INCIDENCIA;
GO

select top (10)
    DIM_TIEMPO.id_tiempo,
    DIM_TIEMPO.fecha,
    DIM_TIEMPO.anio,
    DIM_TIEMPO.mes,
    DIM_TIEMPO.nombre_mes
from dbo.DIM_TIEMPO
order by DIM_TIEMPO.id_tiempo desc;
GO

select count(*) as filas from dbo.FACT_CONSUMO;
select count(*) as filas from dbo.FACT_FACTURACION;
select count(*) as filas from dbo.FACT_PAGO;
select count(*) as filas from dbo.FACT_MOROSIDAD;
select count(*) as filas from dbo.FACT_MANTENIMIENTO;
select count(*) as filas from dbo.FACT_INCIDENCIA;
GO

   --Consumo por mes (GET /dw/consumo?por=mes)
declare @anio int = null;

select
    DIM_TIEMPO.anio,
    DIM_TIEMPO.mes,
    DIM_TIEMPO.nombre_mes,
    count(*) as lecturas,
    sum(FACT_CONSUMO.consumo_m3) as consumo_total_m3,
    cast(avg(FACT_CONSUMO.consumo_m3) as decimal(10,2)) as consumo_promedio_m3
from dbo.FACT_CONSUMO
inner join dbo.DIM_TIEMPO
    on DIM_TIEMPO.id_tiempo = FACT_CONSUMO.id_tiempo
inner join dbo.DIM_CONEXION
    on DIM_CONEXION.id_conexion_dw = FACT_CONSUMO.id_conexion_dw
inner join dbo.DIM_TARIFA
    on DIM_TARIFA.id_tarifa_dw = FACT_CONSUMO.id_tarifa_dw
where @anio is null or DIM_TIEMPO.anio = @anio
group by DIM_TIEMPO.anio, DIM_TIEMPO.mes, DIM_TIEMPO.nombre_mes
order by DIM_TIEMPO.anio, DIM_TIEMPO.mes;
GO

   --Consumo por distrito (GET /dw/consumo?por=distrito)
declare @anio int = null;

select
    isnull(DIM_CONEXION.distrito, 'Sin distrito') as distrito,
    count(*) as lecturas,
    sum(FACT_CONSUMO.consumo_m3) as consumo_total_m3,
    cast(avg(FACT_CONSUMO.consumo_m3) as decimal(10,2)) as consumo_promedio_m3
from dbo.FACT_CONSUMO
inner join dbo.DIM_TIEMPO
    on DIM_TIEMPO.id_tiempo = FACT_CONSUMO.id_tiempo
inner join dbo.DIM_CONEXION
    on DIM_CONEXION.id_conexion_dw = FACT_CONSUMO.id_conexion_dw
inner join dbo.DIM_TARIFA
    on DIM_TARIFA.id_tarifa_dw = FACT_CONSUMO.id_tarifa_dw
where @anio is null or DIM_TIEMPO.anio = @anio
group by isnull(DIM_CONEXION.distrito, 'Sin distrito')
order by 1;
GO

   --Consumo por tarifa (GET /dw/consumo?por=tarifa)
declare @anio int = null;

select
    DIM_TARIFA.tipo_tarifa,
    count(*) as lecturas,
    sum(FACT_CONSUMO.consumo_m3) as consumo_total_m3,
    cast(avg(FACT_CONSUMO.consumo_m3) as decimal(10,2)) as consumo_promedio_m3
from dbo.FACT_CONSUMO
inner join dbo.DIM_TIEMPO
    on DIM_TIEMPO.id_tiempo = FACT_CONSUMO.id_tiempo
inner join dbo.DIM_CONEXION
    on DIM_CONEXION.id_conexion_dw = FACT_CONSUMO.id_conexion_dw
inner join dbo.DIM_TARIFA
    on DIM_TARIFA.id_tarifa_dw = FACT_CONSUMO.id_tarifa_dw
where @anio is null or DIM_TIEMPO.anio = @anio
group by DIM_TARIFA.tipo_tarifa
order by 1;
GO

   --Facturación vs recaudación por mes (GET /dw/facturacion)
declare @anio int = null;

with facturado as (
    select
        DIM_TIEMPO.anio,
        DIM_TIEMPO.mes,
        count(*) as facturas,
        sum(FACT_FACTURACION.monto_total) as monto_facturado
    from dbo.FACT_FACTURACION
    inner join dbo.DIM_TIEMPO
        on DIM_TIEMPO.id_tiempo = FACT_FACTURACION.id_tiempo
    where @anio is null or DIM_TIEMPO.anio = @anio
    group by DIM_TIEMPO.anio, DIM_TIEMPO.mes
),
recaudado as (
    select
        DIM_TIEMPO.anio,
        DIM_TIEMPO.mes,
        count(*) as pagos,
        sum(FACT_PAGO.monto_pagado) as monto_recaudado,
        sum(FACT_PAGO.monto_recargo) as recargos_cobrados
    from dbo.FACT_PAGO
    inner join dbo.DIM_TIEMPO
        on DIM_TIEMPO.id_tiempo = FACT_PAGO.id_tiempo
    where @anio is null or DIM_TIEMPO.anio = @anio
    group by DIM_TIEMPO.anio, DIM_TIEMPO.mes
)
select
    coalesce(facturado.anio, recaudado.anio) as anio,
    coalesce(facturado.mes, recaudado.mes) as mes,
    isnull(facturado.facturas, 0) as facturas,
    isnull(facturado.monto_facturado, 0) as monto_facturado,
    isnull(recaudado.pagos, 0) as pagos,
    isnull(recaudado.monto_recaudado, 0) as monto_recaudado,
    isnull(recaudado.recargos_cobrados, 0) as recargos_cobrados
from facturado
full join recaudado
    on recaudado.anio = facturado.anio and recaudado.mes = facturado.mes
order by 1, 2;
GO

   --Morosidad por distrito (GET /dw/morosidad)
declare @fecha_corte int = null;

declare @corte int = coalesce(
    @fecha_corte,
    (select max(FACT_MOROSIDAD.id_tiempo) from dbo.FACT_MOROSIDAD));

select
    @corte as fecha_corte,
    isnull(DIM_CONEXION.distrito, 'Sin distrito') as distrito,
    count(distinct FACT_MOROSIDAD.id_abonado_dw) as abonados_morosos,
    sum(FACT_MOROSIDAD.cantidad_facturas_ven) as facturas_vencidas,
    sum(FACT_MOROSIDAD.saldo_vencido) as saldo_vencido
from dbo.FACT_MOROSIDAD
inner join dbo.DIM_CONEXION
    on DIM_CONEXION.id_conexion_dw = FACT_MOROSIDAD.id_conexion_dw
where FACT_MOROSIDAD.id_tiempo = @corte
group by DIM_CONEXION.distrito
order by saldo_vencido desc;
GO

   --Mantenimientos por tipo (GET /dw/mantenimientos?por=tipo)
declare @anio int = null;

select
    DIM_TIPO_TRABAJO.nombre_trabajo as tipo_trabajo,
    count(*) as mantenimientos,
    cast(avg(cast(FACT_MANTENIMIENTO.dias_resolucion as decimal(10,2))) as decimal(10,2)) as dias_promedio_resolucion,
    sum(case when FACT_MANTENIMIENTO.estado_final = 'Finalizado' then 1 else 0 end) as finalizados
from dbo.FACT_MANTENIMIENTO
inner join dbo.DIM_TIEMPO
    on DIM_TIEMPO.id_tiempo = FACT_MANTENIMIENTO.id_tiempo
inner join dbo.DIM_TIPO_TRABAJO
    on DIM_TIPO_TRABAJO.id_tipo_trabajo_dw = FACT_MANTENIMIENTO.id_tipo_trabajo_dw
where @anio is null or DIM_TIEMPO.anio = @anio
group by DIM_TIPO_TRABAJO.nombre_trabajo
order by mantenimientos desc;
GO

   --Mantenimientos por empleado (GET /dw/mantenimientos?por=empleado)
declare @anio int = null;

select
    DIM_EMPLEADO.nombre_empleado as empleado,
    count(*) as mantenimientos,
    cast(avg(cast(FACT_MANTENIMIENTO.dias_resolucion as decimal(10,2))) as decimal(10,2)) as dias_promedio_resolucion,
    sum(case when FACT_MANTENIMIENTO.estado_final = 'Finalizado' then 1 else 0 end) as finalizados
from dbo.FACT_MANTENIMIENTO
inner join dbo.DIM_TIEMPO
    on DIM_TIEMPO.id_tiempo = FACT_MANTENIMIENTO.id_tiempo
inner join dbo.DIM_EMPLEADO
    on DIM_EMPLEADO.id_empleado_dw = FACT_MANTENIMIENTO.id_empleado_dw
where @anio is null or DIM_TIEMPO.anio = @anio
group by DIM_EMPLEADO.nombre_empleado
order by mantenimientos desc;
GO

   --Incidencias por tipo (GET /dw/incidencias?por=tipo)
declare @anio int = null;
declare @id_tipo_incidencia int = null;

select
    DIM_TIPO_INCIDENCIA.nombre_incidencia as tipo_incidencia,
    count(*) as incidencias,
    sum(case when FACT_INCIDENCIA.estado = 'Abierta' then 1 else 0 end) as abiertas,
    sum(case when FACT_INCIDENCIA.estado = 'En proceso' then 1 else 0 end) as en_proceso,
    sum(case when FACT_INCIDENCIA.estado = 'Resuelta' then 1 else 0 end) as resueltas,
    cast(avg(cast(FACT_INCIDENCIA.dias_atencion as decimal(10,2))) as decimal(10,2)) as dias_promedio_atencion
from dbo.FACT_INCIDENCIA
inner join dbo.DIM_TIEMPO
    on DIM_TIEMPO.id_tiempo = FACT_INCIDENCIA.id_tiempo
inner join dbo.DIM_TIPO_INCIDENCIA
    on DIM_TIPO_INCIDENCIA.id_tipo_incidencia_dw = FACT_INCIDENCIA.id_tipo_incidencia_dw
where (@anio is null or DIM_TIEMPO.anio = @anio)
  and (@id_tipo_incidencia is null or DIM_TIPO_INCIDENCIA.id_tipo_incidencia_origen = @id_tipo_incidencia)
group by DIM_TIPO_INCIDENCIA.nombre_incidencia
order by incidencias desc;
GO

   --Incidencias por mes (GET /dw/incidencias?por=mes)
declare @anio int = null;
declare @id_tipo_incidencia int = null;

select
    DIM_TIEMPO.anio,
    DIM_TIEMPO.mes,
    DIM_TIEMPO.nombre_mes,
    count(*) as incidencias,
    sum(case when FACT_INCIDENCIA.estado = 'Abierta' then 1 else 0 end) as abiertas,
    sum(case when FACT_INCIDENCIA.estado = 'En proceso' then 1 else 0 end) as en_proceso,
    sum(case when FACT_INCIDENCIA.estado = 'Resuelta' then 1 else 0 end) as resueltas,
    cast(avg(cast(FACT_INCIDENCIA.dias_atencion as decimal(10,2))) as decimal(10,2)) as dias_promedio_atencion
from dbo.FACT_INCIDENCIA
inner join dbo.DIM_TIEMPO
    on DIM_TIEMPO.id_tiempo = FACT_INCIDENCIA.id_tiempo
inner join dbo.DIM_TIPO_INCIDENCIA
    on DIM_TIPO_INCIDENCIA.id_tipo_incidencia_dw = FACT_INCIDENCIA.id_tipo_incidencia_dw
where (@anio is null or DIM_TIEMPO.anio = @anio)
  and (@id_tipo_incidencia is null or DIM_TIPO_INCIDENCIA.id_tipo_incidencia_origen = @id_tipo_incidencia)
group by DIM_TIEMPO.anio, DIM_TIEMPO.mes, DIM_TIEMPO.nombre_mes
order by DIM_TIEMPO.anio, DIM_TIEMPO.mes;
GO

   --Incidencias por prioridad (GET /dw/incidencias?por=prioridad)
declare @anio int = null;
declare @id_tipo_incidencia int = null;

select
    isnull(FACT_INCIDENCIA.prioridad, 'Sin prioridad') as prioridad,
    count(*) as incidencias,
    sum(case when FACT_INCIDENCIA.estado = 'Abierta' then 1 else 0 end) as abiertas,
    sum(case when FACT_INCIDENCIA.estado = 'En proceso' then 1 else 0 end) as en_proceso,
    sum(case when FACT_INCIDENCIA.estado = 'Resuelta' then 1 else 0 end) as resueltas,
    cast(avg(cast(FACT_INCIDENCIA.dias_atencion as decimal(10,2))) as decimal(10,2)) as dias_promedio_atencion
from dbo.FACT_INCIDENCIA
inner join dbo.DIM_TIEMPO
    on DIM_TIEMPO.id_tiempo = FACT_INCIDENCIA.id_tiempo
inner join dbo.DIM_TIPO_INCIDENCIA
    on DIM_TIPO_INCIDENCIA.id_tipo_incidencia_dw = FACT_INCIDENCIA.id_tipo_incidencia_dw
where (@anio is null or DIM_TIEMPO.anio = @anio)
  and (@id_tipo_incidencia is null or DIM_TIPO_INCIDENCIA.id_tipo_incidencia_origen = @id_tipo_incidencia)
group by isnull(FACT_INCIDENCIA.prioridad, 'Sin prioridad')
order by incidencias desc;
GO

USE ASADA;
GO

   --Validación y conciliación (misma lógica que la aplicación y el ETL)
exec dbo.sp_ValidarCargaDW;
GO

   --Periodo fiscal AAAAMM; ajuste al mes que desee conciliar
declare @periodo int = 202601;
exec dbo.sp_ConciliarOrigenDW @periodo = @periodo;
GO

select
    vw_UltimaCargaPorTabla.nombre_tabla_destino,
    vw_UltimaCargaPorTabla.fecha_ultima_carga,
    vw_UltimaCargaPorTabla.filas_procesadas,
    vw_UltimaCargaPorTabla.estado
from dbo.vw_UltimaCargaPorTabla
order by vw_UltimaCargaPorTabla.nombre_tabla_destino;
GO

PRINT 'Consultas de demostración del Data Warehouse finalizadas.';
GO
