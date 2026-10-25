SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Script 13: Data Warehouse (R5)
   - Las tablas DIM_* y FACT_* se crean en la base ASADA_DW.
   - Los procedimientos ETL viven en ASADA (junto a Control_ETL) y escriben
     en ASADA_DW con nombres de tres partes.
   - Cada hecho guarda el id de origen (columna id_*_origen) para que la
     carga sea incremental y no duplique registros al reintentarse.
   ===================================================================== */
USE ASADA_DW;
GO

/* ---------------------------------------------------------------------
   Dimensiones
   --------------------------------------------------------------------- */
CREATE TABLE dbo.DIM_TIEMPO (
    id_tiempo   int         NOT NULL,   -- clave inteligente AAAAMMDD
    fecha       date        NOT NULL,
    anio        int         NOT NULL,
    trimestre   int         NOT NULL,
    mes         int         NOT NULL,
    nombre_mes  varchar(20) NOT NULL,
    CONSTRAINT PK_DIM_TIEMPO PRIMARY KEY (id_tiempo),
    CONSTRAINT UQ_DIM_TIEMPO_Fecha UNIQUE (fecha)
) ON DW_Dimensiones;
GO

CREATE TABLE dbo.DIM_ABONADO (
    id_abonado_dw        int IDENTITY(1,1) NOT NULL,
    id_abonado_origen    int          NOT NULL,
    tipo_abonado         varchar(10)  NOT NULL,
    nombre_razon_social  varchar(100) NOT NULL,
    distrito_residencia  varchar(50)  NULL,
    CONSTRAINT PK_DIM_ABONADO PRIMARY KEY (id_abonado_dw),
    -- Los id de físicos y jurídicos se repiten entre sí, por eso la clave natural incluye el tipo.
    CONSTRAINT UQ_DIM_ABONADO_Origen UNIQUE (tipo_abonado, id_abonado_origen)
) ON DW_Dimensiones;
GO

CREATE TABLE dbo.DIM_CONEXION (
    id_conexion_dw      int IDENTITY(1,1) NOT NULL,
    id_conexion_origen  int         NOT NULL,
    ubicacion           varchar(50) NOT NULL,
    distrito            varchar(50) NULL,
    estado_actual       varchar(50) NOT NULL,
    CONSTRAINT PK_DIM_CONEXION PRIMARY KEY (id_conexion_dw),
    CONSTRAINT UQ_DIM_CONEXION_Origen UNIQUE (id_conexion_origen)
) ON DW_Dimensiones;
GO

CREATE TABLE dbo.DIM_TARIFA (
    id_tarifa_dw      int IDENTITY(1,1) NOT NULL,
    id_tarifa_origen  int           NOT NULL,
    nombre_tarifa     varchar(20)   NOT NULL,
    tipo_tarifa       varchar(20)   NOT NULL,
    monto_fijo        decimal(10,2) NOT NULL,
    monto_por_m3      decimal(10,2) NOT NULL,
    CONSTRAINT PK_DIM_TARIFA PRIMARY KEY (id_tarifa_dw),
    CONSTRAINT UQ_DIM_TARIFA_Origen UNIQUE (id_tarifa_origen)
) ON DW_Dimensiones;
GO

CREATE TABLE dbo.DIM_TIPO_TRABAJO (
    id_tipo_trabajo_dw      int IDENTITY(1,1) NOT NULL,
    id_tipo_trabajo_origen  int         NOT NULL,
    nombre_trabajo          varchar(20) NOT NULL,
    CONSTRAINT PK_DIM_TIPO_TRABAJO PRIMARY KEY (id_tipo_trabajo_dw),
    CONSTRAINT UQ_DIM_TIPO_TRABAJO_Origen UNIQUE (id_tipo_trabajo_origen)
) ON DW_Dimensiones;
GO

CREATE TABLE dbo.DIM_EMPLEADO (
    id_empleado_dw      int IDENTITY(1,1) NOT NULL,
    id_empleado_origen  int         NOT NULL,
    nombre_empleado     varchar(50) NOT NULL,
    puesto              varchar(50) NOT NULL,
    CONSTRAINT PK_DIM_EMPLEADO PRIMARY KEY (id_empleado_dw),
    CONSTRAINT UQ_DIM_EMPLEADO_Origen UNIQUE (id_empleado_origen)
) ON DW_Dimensiones;
GO

/* ---------------------------------------------------------------------
   Hechos
   --------------------------------------------------------------------- */
CREATE TABLE dbo.FACT_CONSUMO (
    id_consumo         int IDENTITY(1,1) NOT NULL,
    id_lectura_origen  int           NOT NULL,
    id_tiempo          int           NOT NULL,
    id_abonado_dw      int           NOT NULL,
    id_conexion_dw     int           NOT NULL,
    id_tarifa_dw       int           NOT NULL,
    lectura_anterior   decimal(10,2) NOT NULL,
    lectura_actual     decimal(10,2) NOT NULL,
    consumo_m3         decimal(10,2) NOT NULL,
    fecha_carga_dw     datetime      NOT NULL CONSTRAINT DF_FACT_CONSUMO_Carga DEFAULT (GETDATE()),
    CONSTRAINT PK_FACT_CONSUMO PRIMARY KEY (id_consumo),
    CONSTRAINT UQ_FACT_CONSUMO_Origen UNIQUE (id_lectura_origen),
    CONSTRAINT FK_FACT_CONSUMO_Tiempo   FOREIGN KEY (id_tiempo)      REFERENCES dbo.DIM_TIEMPO (id_tiempo),
    CONSTRAINT FK_FACT_CONSUMO_Abonado  FOREIGN KEY (id_abonado_dw)  REFERENCES dbo.DIM_ABONADO (id_abonado_dw),
    CONSTRAINT FK_FACT_CONSUMO_Conexion FOREIGN KEY (id_conexion_dw) REFERENCES dbo.DIM_CONEXION (id_conexion_dw),
    CONSTRAINT FK_FACT_CONSUMO_Tarifa   FOREIGN KEY (id_tarifa_dw)   REFERENCES dbo.DIM_TARIFA (id_tarifa_dw)
) ON DW_Hechos;
GO

CREATE TABLE dbo.FACT_FACTURACION (
    id_facturacion     int IDENTITY(1,1) NOT NULL,
    id_factura_origen  int           NOT NULL,
    id_tiempo          int           NOT NULL,
    id_abonado_dw      int           NOT NULL,
    id_conexion_dw     int           NOT NULL,
    id_tarifa_dw       int           NOT NULL,
    monto_consumo      decimal(10,2) NOT NULL,
    monto_fijo         decimal(10,2) NOT NULL,
    monto_total        decimal(10,2) NOT NULL,
    estado             varchar(20)   NOT NULL,
    fecha_carga_dw     datetime      NOT NULL CONSTRAINT DF_FACT_FACTURACION_Carga DEFAULT (GETDATE()),
    CONSTRAINT PK_FACT_FACTURACION PRIMARY KEY (id_facturacion),
    CONSTRAINT UQ_FACT_FACTURACION_Origen UNIQUE (id_factura_origen),
    CONSTRAINT FK_FACT_FACTURACION_Tiempo   FOREIGN KEY (id_tiempo)      REFERENCES dbo.DIM_TIEMPO (id_tiempo),
    CONSTRAINT FK_FACT_FACTURACION_Abonado  FOREIGN KEY (id_abonado_dw)  REFERENCES dbo.DIM_ABONADO (id_abonado_dw),
    CONSTRAINT FK_FACT_FACTURACION_Conexion FOREIGN KEY (id_conexion_dw) REFERENCES dbo.DIM_CONEXION (id_conexion_dw),
    CONSTRAINT FK_FACT_FACTURACION_Tarifa   FOREIGN KEY (id_tarifa_dw)   REFERENCES dbo.DIM_TARIFA (id_tarifa_dw)
) ON DW_Hechos;
GO

CREATE TABLE dbo.FACT_PAGO (
    id_pago_dw      int IDENTITY(1,1) NOT NULL,
    id_pago_origen  int           NOT NULL,
    id_tiempo       int           NOT NULL,
    id_abonado_dw   int           NOT NULL,
    id_conexion_dw  int           NOT NULL,
    monto_pagado    decimal(10,2) NOT NULL,
    monto_recargo   decimal(10,2) NOT NULL,
    fecha_carga_dw  datetime      NOT NULL CONSTRAINT DF_FACT_PAGO_Carga DEFAULT (GETDATE()),
    CONSTRAINT PK_FACT_PAGO PRIMARY KEY (id_pago_dw),
    CONSTRAINT UQ_FACT_PAGO_Origen UNIQUE (id_pago_origen),
    CONSTRAINT FK_FACT_PAGO_Tiempo   FOREIGN KEY (id_tiempo)      REFERENCES dbo.DIM_TIEMPO (id_tiempo),
    CONSTRAINT FK_FACT_PAGO_Abonado  FOREIGN KEY (id_abonado_dw)  REFERENCES dbo.DIM_ABONADO (id_abonado_dw),
    CONSTRAINT FK_FACT_PAGO_Conexion FOREIGN KEY (id_conexion_dw) REFERENCES dbo.DIM_CONEXION (id_conexion_dw)
) ON DW_Hechos;
GO

CREATE TABLE dbo.FACT_MOROSIDAD (
    id_morosidad           int IDENTITY(1,1) NOT NULL,
    id_tiempo              int           NOT NULL,   -- fecha de corte
    id_abonado_dw          int           NOT NULL,
    id_conexion_dw         int           NOT NULL,
    saldo_vencido          decimal(10,2) NOT NULL,
    cantidad_facturas_ven  int           NOT NULL,
    fecha_carga_dw         datetime      NOT NULL CONSTRAINT DF_FACT_MOROSIDAD_Carga DEFAULT (GETDATE()),
    CONSTRAINT PK_FACT_MOROSIDAD PRIMARY KEY (id_morosidad),
    CONSTRAINT UQ_FACT_MOROSIDAD_Corte UNIQUE (id_tiempo, id_conexion_dw),
    CONSTRAINT FK_FACT_MOROSIDAD_Tiempo   FOREIGN KEY (id_tiempo)      REFERENCES dbo.DIM_TIEMPO (id_tiempo),
    CONSTRAINT FK_FACT_MOROSIDAD_Abonado  FOREIGN KEY (id_abonado_dw)  REFERENCES dbo.DIM_ABONADO (id_abonado_dw),
    CONSTRAINT FK_FACT_MOROSIDAD_Conexion FOREIGN KEY (id_conexion_dw) REFERENCES dbo.DIM_CONEXION (id_conexion_dw)
) ON DW_Hechos;
GO

CREATE TABLE dbo.FACT_MANTENIMIENTO (
    id_fact_mantenimiento_dw  int IDENTITY(1,1) NOT NULL,
    id_mantenimiento_origen   int         NOT NULL,
    id_tiempo                 int         NOT NULL,   -- fecha de cierre
    id_tipo_trabajo_dw        int         NOT NULL,
    id_empleado_dw            int         NOT NULL,
    id_conexion_dw            int         NOT NULL,
    dias_resolucion           int         NOT NULL,
    estado_final              varchar(20) NOT NULL,
    fecha_carga_dw            datetime    NOT NULL CONSTRAINT DF_FACT_MANTENIMIENTO_Carga DEFAULT (GETDATE()),
    CONSTRAINT PK_FACT_MANTENIMIENTO PRIMARY KEY (id_fact_mantenimiento_dw),
    CONSTRAINT UQ_FACT_MANTENIMIENTO_Origen UNIQUE (id_mantenimiento_origen),
    CONSTRAINT FK_FACT_MANTENIMIENTO_Tiempo      FOREIGN KEY (id_tiempo)          REFERENCES dbo.DIM_TIEMPO (id_tiempo),
    CONSTRAINT FK_FACT_MANTENIMIENTO_TipoTrabajo FOREIGN KEY (id_tipo_trabajo_dw) REFERENCES dbo.DIM_TIPO_TRABAJO (id_tipo_trabajo_dw),
    CONSTRAINT FK_FACT_MANTENIMIENTO_Empleado    FOREIGN KEY (id_empleado_dw)     REFERENCES dbo.DIM_EMPLEADO (id_empleado_dw),
    CONSTRAINT FK_FACT_MANTENIMIENTO_Conexion    FOREIGN KEY (id_conexion_dw)     REFERENCES dbo.DIM_CONEXION (id_conexion_dw)
) ON DW_Hechos;
GO

/* =====================================================================
   Procedimientos ETL (en la base ASADA)
   ===================================================================== */
USE ASADA;
GO

-- Toma la primera parte de una dirección o ubicación como distrito.
-- Ej.: 'Nicoya, 200 m norte del parque' -> 'Nicoya'
CREATE OR ALTER FUNCTION dbo.fn_ExtraerDistrito (@texto varchar(200))
RETURNS varchar(50)
AS
BEGIN
    RETURN LEFT(LTRIM(RTRIM(LEFT(@texto, CHARINDEX(',', @texto + ',') - 1))), 50);
END;
GO

-- Clave AAAAMMDD de DIM_TIEMPO para una fecha.
CREATE OR ALTER FUNCTION dbo.fn_IdTiempo (@fecha datetime)
RETURNS int
AS
BEGIN
    RETURN YEAR(@fecha) * 10000 + MONTH(@fecha) * 100 + DAY(@fecha);
END;
GO

/* ---------------------------------------------------------------------
   Control de ejecución (Control_ETL)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_ETL_IniciarControl
    @nombre_tabla_destino varchar(50),
    @id_proceso_etl       int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Control_ETL (nombre_tabla_destino, fecha_proceso, estado)
    VALUES (@nombre_tabla_destino, GETDATE(), 'En proceso');

    SET @id_proceso_etl = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ETL_FinalizarControl
    @id_proceso_etl  int,
    @estado          varchar(20),
    @filas           int          = 0,
    @mensaje_error   varchar(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Control_ETL
    SET estado = @estado,
        filas_procesadas = ISNULL(@filas, 0),
        mensaje_error = @mensaje_error,
        fecha_ultima_carga = CASE WHEN @estado = 'Exitoso' THEN fecha_proceso END
    WHERE id_proceso_etl = @id_proceso_etl;
END;
GO

-- Fecha desde la que se extrae: última carga exitosa menos un margen de 60 días
-- para recoger correcciones (lecturas corregidas, pagos anulados, cambios de estado).
CREATE OR ALTER FUNCTION dbo.fn_ETL_FechaDesde (@nombre_tabla_destino varchar(50))
RETURNS datetime
AS
BEGIN
    DECLARE @ultima datetime;

    SELECT @ultima = MAX(fecha_ultima_carga)
    FROM dbo.Control_ETL
    WHERE nombre_tabla_destino = @nombre_tabla_destino AND estado = 'Exitoso';

    RETURN ISNULL(DATEADD(DAY, -60, @ultima), '19000101');
END;
GO

/* ---------------------------------------------------------------------
   Dimensiones
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_ETL_CargarDimTiempo
    @desde date,
    @hasta date
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH n AS (
        SELECT TOP (DATEDIFF(DAY, @desde, @hasta) + 1)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    ), fechas AS (
        SELECT DATEADD(DAY, i, @desde) AS fecha FROM n
    )
    INSERT INTO ASADA_DW.dbo.DIM_TIEMPO (id_tiempo, fecha, anio, trimestre, mes, nombre_mes)
    SELECT dbo.fn_IdTiempo(f.fecha), f.fecha, YEAR(f.fecha), DATEPART(QUARTER, f.fecha), MONTH(f.fecha),
           CHOOSE(MONTH(f.fecha), 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
                  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre')
    FROM fechas f
    WHERE NOT EXISTS (SELECT 1 FROM ASADA_DW.dbo.DIM_TIEMPO t WHERE t.fecha = f.fecha);

    RETURN @@ROWCOUNT;
END;
GO

-- Carga las dimensiones antes que los hechos (tipo 1: se sobrescriben los cambios).
CREATE OR ALTER PROCEDURE dbo.sp_ETL_CargarDimensionesDW
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @id int, @filas int = 0, @n int, @desde date, @mensaje varchar(500);
    EXEC dbo.sp_ETL_IniciarControl 'DIMENSIONES', @id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- DIM_TIEMPO: desde la fecha más antigua del origen hasta fin del año siguiente.
        SELECT @desde = MIN(f) FROM (
            SELECT MIN(CAST(fecha_lectura_actual AS date)) FROM dbo.Lectura
            UNION ALL SELECT MIN(CAST(fecha_emision AS date)) FROM dbo.Factura
            UNION ALL SELECT MIN(fecha_pago) FROM dbo.Pago
            UNION ALL SELECT MIN(CAST(fecha_inicio AS date)) FROM dbo.Mantenimiento
        ) x(f);
        SET @desde = ISNULL(@desde, CAST(GETDATE() AS date));

        DECLARE @hasta date = DATEFROMPARTS(YEAR(GETDATE()) + 1, 12, 31);
        EXEC @n = dbo.sp_ETL_CargarDimTiempo @desde, @hasta;
        SET @filas += @n;

        MERGE ASADA_DW.dbo.DIM_ABONADO AS d
        USING (SELECT tipo_abonado, id_abonado, LEFT(nombre_completo, 100) AS nombre,
                      dbo.fn_ExtraerDistrito(direccion) AS distrito
               FROM dbo.vw_Abonados) AS o
           ON d.tipo_abonado = o.tipo_abonado AND d.id_abonado_origen = o.id_abonado
        WHEN MATCHED AND (d.nombre_razon_social <> o.nombre OR ISNULL(d.distrito_residencia, '') <> ISNULL(o.distrito, ''))
            THEN UPDATE SET nombre_razon_social = o.nombre, distrito_residencia = o.distrito
        WHEN NOT MATCHED
            THEN INSERT (id_abonado_origen, tipo_abonado, nombre_razon_social, distrito_residencia)
                 VALUES (o.id_abonado, o.tipo_abonado, o.nombre, o.distrito);
        SET @filas += @@ROWCOUNT;

        MERGE ASADA_DW.dbo.DIM_CONEXION AS d
        USING (SELECT id_conexion, ubicacion, dbo.fn_ExtraerDistrito(ubicacion) AS distrito, estado FROM dbo.Conexion) AS o
           ON d.id_conexion_origen = o.id_conexion
        WHEN MATCHED AND (d.ubicacion <> o.ubicacion OR d.estado_actual <> o.estado)
            THEN UPDATE SET ubicacion = o.ubicacion, distrito = o.distrito, estado_actual = o.estado
        WHEN NOT MATCHED
            THEN INSERT (id_conexion_origen, ubicacion, distrito, estado_actual)
                 VALUES (o.id_conexion, o.ubicacion, o.distrito, o.estado);
        SET @filas += @@ROWCOUNT;

        MERGE ASADA_DW.dbo.DIM_TARIFA AS d
        USING (SELECT t.id_tarifa, LEFT(CONCAT(tt.nombre_tarifa, ' #', t.id_tarifa), 20) AS nombre,
                      tt.nombre_tarifa AS tipo, t.monto_fijo, t.monto_por_m3
               FROM dbo.Tarifa t JOIN dbo.Tipo_Tarifa tt ON tt.id_tipo_tarifa = t.id_tipo_tarifa) AS o
           ON d.id_tarifa_origen = o.id_tarifa
        WHEN MATCHED AND (d.monto_fijo <> o.monto_fijo OR d.monto_por_m3 <> o.monto_por_m3 OR d.tipo_tarifa <> o.tipo)
            THEN UPDATE SET nombre_tarifa = o.nombre, tipo_tarifa = o.tipo, monto_fijo = o.monto_fijo, monto_por_m3 = o.monto_por_m3
        WHEN NOT MATCHED
            THEN INSERT (id_tarifa_origen, nombre_tarifa, tipo_tarifa, monto_fijo, monto_por_m3)
                 VALUES (o.id_tarifa, o.nombre, o.tipo, o.monto_fijo, o.monto_por_m3);
        SET @filas += @@ROWCOUNT;

        MERGE ASADA_DW.dbo.DIM_TIPO_TRABAJO AS d
        USING (SELECT id_tipo_trabajo, nombre_trabajo FROM dbo.Tipo_Trabajo) AS o
           ON d.id_tipo_trabajo_origen = o.id_tipo_trabajo
        WHEN MATCHED AND d.nombre_trabajo <> o.nombre_trabajo
            THEN UPDATE SET nombre_trabajo = o.nombre_trabajo
        WHEN NOT MATCHED
            THEN INSERT (id_tipo_trabajo_origen, nombre_trabajo) VALUES (o.id_tipo_trabajo, o.nombre_trabajo);
        SET @filas += @@ROWCOUNT;

        MERGE ASADA_DW.dbo.DIM_EMPLEADO AS d
        USING (SELECT id_empleado, LEFT(CONCAT_WS(' ', nombre_empleado, apellido1_empleado, apellido2_empleado), 50) AS nombre, puesto
               FROM dbo.Empleado) AS o
           ON d.id_empleado_origen = o.id_empleado
        WHEN MATCHED AND (d.nombre_empleado <> o.nombre OR d.puesto <> o.puesto)
            THEN UPDATE SET nombre_empleado = o.nombre, puesto = o.puesto
        WHEN NOT MATCHED
            THEN INSERT (id_empleado_origen, nombre_empleado, puesto) VALUES (o.id_empleado, o.nombre, o.puesto);
        SET @filas += @@ROWCOUNT;

        COMMIT;
        EXEC dbo.sp_ETL_FinalizarControl @id, 'Exitoso', @filas;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @mensaje = LEFT(ERROR_MESSAGE(), 500);
        EXEC dbo.sp_ETL_FinalizarControl @id, 'Fallido', 0, @mensaje;
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   Hechos
   --------------------------------------------------------------------- */
-- Lecturas y consumos -> FACT_CONSUMO
CREATE OR ALTER PROCEDURE dbo.sp_ETL_CargaLecturasDW
    @desde datetime = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @id int, @filas int, @mensaje varchar(500);
    SET @desde = ISNULL(@desde, dbo.fn_ETL_FechaDesde('FACT_CONSUMO'));
    EXEC dbo.sp_ETL_IniciarControl 'FACT_CONSUMO', @id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ASADA_DW.dbo.FACT_CONSUMO AS d
        USING (
            SELECT l.id_lectura, dbo.fn_IdTiempo(l.fecha_lectura_actual) AS id_tiempo,
                   da.id_abonado_dw, dc.id_conexion_dw, dt.id_tarifa_dw,
                   l.lectura_anterior, l.lectura_actual, l.consumo
            FROM dbo.Lectura l
            JOIN dbo.Medidor  m ON m.id_medidor = l.id_medidor
            JOIN dbo.Conexion c ON c.id_conexion = m.id_conexion
            JOIN ASADA_DW.dbo.DIM_ABONADO da
              ON (da.tipo_abonado = 'FISICO'   AND da.id_abonado_origen = c.id_abonado_fisico)
              OR (da.tipo_abonado = 'JURIDICO' AND da.id_abonado_origen = c.id_abonado_juridico)
            JOIN ASADA_DW.dbo.DIM_CONEXION dc ON dc.id_conexion_origen = c.id_conexion
            JOIN ASADA_DW.dbo.DIM_TARIFA   dt ON dt.id_tarifa_origen = c.id_tarifa
            WHERE l.fecha_lectura_actual >= @desde
        ) AS o
           ON d.id_lectura_origen = o.id_lectura
        WHEN MATCHED AND (d.lectura_actual <> o.lectura_actual OR d.lectura_anterior <> o.lectura_anterior)
            THEN UPDATE SET lectura_anterior = o.lectura_anterior, lectura_actual = o.lectura_actual,
                            consumo_m3 = o.consumo, fecha_carga_dw = GETDATE()
        WHEN NOT MATCHED
            THEN INSERT (id_lectura_origen, id_tiempo, id_abonado_dw, id_conexion_dw, id_tarifa_dw,
                         lectura_anterior, lectura_actual, consumo_m3)
                 VALUES (o.id_lectura, o.id_tiempo, o.id_abonado_dw, o.id_conexion_dw, o.id_tarifa_dw,
                         o.lectura_anterior, o.lectura_actual, o.consumo);
        SET @filas = @@ROWCOUNT;

        COMMIT;
        EXEC dbo.sp_ETL_FinalizarControl @id, 'Exitoso', @filas;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @mensaje = LEFT(ERROR_MESSAGE(), 500);
        EXEC dbo.sp_ETL_FinalizarControl @id, 'Fallido', 0, @mensaje;
        THROW;
    END CATCH
END;
GO

-- Facturas -> FACT_FACTURACION y pagos -> FACT_PAGO.
-- El recargo incluido en cada pago se calcula de forma proporcional:
-- monto_pagado × recargos / (total + recargos) de la factura.
CREATE OR ALTER PROCEDURE dbo.sp_ETL_CargaFacturacionDW
    @desde datetime = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @id_fact int, @id_pago int, @filas int, @mensaje varchar(500),
            @desde_fact datetime, @desde_pago datetime;

    SET @desde_fact = ISNULL(@desde, dbo.fn_ETL_FechaDesde('FACT_FACTURACION'));
    SET @desde_pago = ISNULL(@desde, dbo.fn_ETL_FechaDesde('FACT_PAGO'));

    /* ---------- FACT_FACTURACION ---------- */
    EXEC dbo.sp_ETL_IniciarControl 'FACT_FACTURACION', @id_fact OUTPUT;
    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ASADA_DW.dbo.FACT_FACTURACION AS d
        USING (
            SELECT f.id_factura, dbo.fn_IdTiempo(f.fecha_emision) AS id_tiempo,
                   da.id_abonado_dw, dc.id_conexion_dw, dt.id_tarifa_dw,
                   f.monto_consumo, f.monto_fijo, f.monto_total, f.estado
            FROM dbo.Factura f
            JOIN dbo.Lectura  l ON l.id_lectura = f.id_lectura
            JOIN dbo.Medidor  m ON m.id_medidor = l.id_medidor
            JOIN dbo.Conexion c ON c.id_conexion = m.id_conexion
            JOIN ASADA_DW.dbo.DIM_ABONADO da
              ON (da.tipo_abonado = 'FISICO'   AND da.id_abonado_origen = c.id_abonado_fisico)
              OR (da.tipo_abonado = 'JURIDICO' AND da.id_abonado_origen = c.id_abonado_juridico)
            JOIN ASADA_DW.dbo.DIM_CONEXION dc ON dc.id_conexion_origen = c.id_conexion
            JOIN ASADA_DW.dbo.DIM_TARIFA   dt ON dt.id_tarifa_origen = c.id_tarifa
            WHERE f.fecha_emision >= @desde_fact OR f.fecha_modificacion >= @desde_fact
        ) AS o
           ON d.id_factura_origen = o.id_factura
        WHEN MATCHED AND d.estado <> o.estado
            THEN UPDATE SET estado = o.estado, fecha_carga_dw = GETDATE()
        WHEN NOT MATCHED
            THEN INSERT (id_factura_origen, id_tiempo, id_abonado_dw, id_conexion_dw, id_tarifa_dw,
                         monto_consumo, monto_fijo, monto_total, estado)
                 VALUES (o.id_factura, o.id_tiempo, o.id_abonado_dw, o.id_conexion_dw, o.id_tarifa_dw,
                         o.monto_consumo, o.monto_fijo, o.monto_total, o.estado);
        SET @filas = @@ROWCOUNT;

        COMMIT;
        EXEC dbo.sp_ETL_FinalizarControl @id_fact, 'Exitoso', @filas;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @mensaje = LEFT(ERROR_MESSAGE(), 500);
        EXEC dbo.sp_ETL_FinalizarControl @id_fact, 'Fallido', 0, @mensaje;
        THROW;
    END CATCH

    /* ---------- FACT_PAGO ---------- */
    EXEC dbo.sp_ETL_IniciarControl 'FACT_PAGO', @id_pago OUTPUT;
    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ASADA_DW.dbo.FACT_PAGO AS d
        USING (
            SELECT p.id_pago, dbo.fn_IdTiempo(p.fecha_pago) AS id_tiempo,
                   da.id_abonado_dw, dc.id_conexion_dw, p.monto,
                   CAST(CASE WHEN s.monto_total + s.recargos > 0
                             THEN p.monto * s.recargos / (s.monto_total + s.recargos) ELSE 0 END AS decimal(10,2)) AS recargo
            FROM dbo.Pago p
            JOIN dbo.vw_SaldoFactura s ON s.id_factura = p.id_factura
            JOIN dbo.Conexion c        ON c.id_conexion = s.id_conexion
            JOIN ASADA_DW.dbo.DIM_ABONADO da
              ON (da.tipo_abonado = 'FISICO'   AND da.id_abonado_origen = c.id_abonado_fisico)
              OR (da.tipo_abonado = 'JURIDICO' AND da.id_abonado_origen = c.id_abonado_juridico)
            JOIN ASADA_DW.dbo.DIM_CONEXION dc ON dc.id_conexion_origen = c.id_conexion
            WHERE p.estado = 'Aplicado' AND p.fecha_pago >= CAST(@desde_pago AS date)
        ) AS o
           ON d.id_pago_origen = o.id_pago
        WHEN MATCHED AND d.monto_recargo <> o.recargo
            THEN UPDATE SET monto_recargo = o.recargo, fecha_carga_dw = GETDATE()
        WHEN NOT MATCHED
            THEN INSERT (id_pago_origen, id_tiempo, id_abonado_dw, id_conexion_dw, monto_pagado, monto_recargo)
                 VALUES (o.id_pago, o.id_tiempo, o.id_abonado_dw, o.id_conexion_dw, o.monto, o.recargo);
        SET @filas = @@ROWCOUNT;

        -- Los pagos anulados se retiran del Data Warehouse.
        DELETE d
        FROM ASADA_DW.dbo.FACT_PAGO d
        JOIN dbo.Pago p ON p.id_pago = d.id_pago_origen
        WHERE p.estado = 'Anulado';
        SET @filas += @@ROWCOUNT;

        COMMIT;
        EXEC dbo.sp_ETL_FinalizarControl @id_pago, 'Exitoso', @filas;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @mensaje = LEFT(ERROR_MESSAGE(), 500);
        EXEC dbo.sp_ETL_FinalizarControl @id_pago, 'Fallido', 0, @mensaje;
        THROW;
    END CATCH
END;
GO

-- Foto de la morosidad a una fecha de corte. Si se ejecuta dos veces el mismo
-- día, reemplaza la foto anterior en lugar de duplicarla.
CREATE OR ALTER PROCEDURE dbo.sp_ETL_CargaMorosidadDW
    @fecha_corte date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @id int, @filas int, @mensaje varchar(500), @id_tiempo int;
    SET @fecha_corte = ISNULL(@fecha_corte, CAST(GETDATE() AS date));
    SET @id_tiempo = dbo.fn_IdTiempo(@fecha_corte);
    EXEC dbo.sp_ETL_IniciarControl 'FACT_MOROSIDAD', @id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC dbo.sp_ETL_CargarDimTiempo @fecha_corte, @fecha_corte;

        DELETE FROM ASADA_DW.dbo.FACT_MOROSIDAD WHERE id_tiempo = @id_tiempo;

        INSERT INTO ASADA_DW.dbo.FACT_MOROSIDAD (id_tiempo, id_abonado_dw, id_conexion_dw, saldo_vencido, cantidad_facturas_ven)
        SELECT @id_tiempo, da.id_abonado_dw, dc.id_conexion_dw, SUM(s.saldo), COUNT(*)
        FROM dbo.vw_SaldoFactura s
        JOIN dbo.Conexion c ON c.id_conexion = s.id_conexion
        JOIN ASADA_DW.dbo.DIM_ABONADO da
          ON (da.tipo_abonado = 'FISICO'   AND da.id_abonado_origen = c.id_abonado_fisico)
          OR (da.tipo_abonado = 'JURIDICO' AND da.id_abonado_origen = c.id_abonado_juridico)
        JOIN ASADA_DW.dbo.DIM_CONEXION dc ON dc.id_conexion_origen = c.id_conexion
        WHERE s.estado <> 'Pagada' AND s.saldo > 0 AND s.fecha_vencimiento < @fecha_corte
        GROUP BY da.id_abonado_dw, dc.id_conexion_dw;
        SET @filas = @@ROWCOUNT;

        COMMIT;
        EXEC dbo.sp_ETL_FinalizarControl @id, 'Exitoso', @filas;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @mensaje = LEFT(ERROR_MESSAGE(), 500);
        EXEC dbo.sp_ETL_FinalizarControl @id, 'Fallido', 0, @mensaje;
        THROW;
    END CATCH
END;
GO

-- Mantenimientos cerrados (finalizados o cancelados) -> FACT_MANTENIMIENTO
CREATE OR ALTER PROCEDURE dbo.sp_ETL_CargaMantenimientosDW
    @desde datetime = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @id int, @filas int, @mensaje varchar(500);
    SET @desde = ISNULL(@desde, dbo.fn_ETL_FechaDesde('FACT_MANTENIMIENTO'));
    EXEC dbo.sp_ETL_IniciarControl 'FACT_MANTENIMIENTO', @id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE ASADA_DW.dbo.FACT_MANTENIMIENTO AS d
        USING (
            SELECT mt.id_mantenimiento, dbo.fn_IdTiempo(mt.fecha_fin) AS id_tiempo,
                   dtt.id_tipo_trabajo_dw, de.id_empleado_dw, dc.id_conexion_dw,
                   DATEDIFF(DAY, mt.fecha_inicio, mt.fecha_fin) AS dias, mt.estado
            FROM dbo.Mantenimiento mt
            JOIN ASADA_DW.dbo.DIM_TIPO_TRABAJO dtt ON dtt.id_tipo_trabajo_origen = mt.id_tipo_trabajo
            JOIN ASADA_DW.dbo.DIM_EMPLEADO     de  ON de.id_empleado_origen = mt.id_empleado
            JOIN ASADA_DW.dbo.DIM_CONEXION     dc  ON dc.id_conexion_origen = mt.id_conexion
            WHERE mt.estado IN ('Finalizado', 'Cancelado')
              AND mt.fecha_fin IS NOT NULL
              AND (mt.fecha_fin >= @desde OR mt.fecha_modificacion >= @desde)
        ) AS o
           ON d.id_mantenimiento_origen = o.id_mantenimiento
        WHEN MATCHED AND (d.estado_final <> o.estado OR d.dias_resolucion <> o.dias)
            THEN UPDATE SET estado_final = o.estado, dias_resolucion = o.dias, id_tiempo = o.id_tiempo, fecha_carga_dw = GETDATE()
        WHEN NOT MATCHED
            THEN INSERT (id_mantenimiento_origen, id_tiempo, id_tipo_trabajo_dw, id_empleado_dw, id_conexion_dw, dias_resolucion, estado_final)
                 VALUES (o.id_mantenimiento, o.id_tiempo, o.id_tipo_trabajo_dw, o.id_empleado_dw, o.id_conexion_dw, o.dias, o.estado);
        SET @filas = @@ROWCOUNT;

        COMMIT;
        EXEC dbo.sp_ETL_FinalizarControl @id, 'Exitoso', @filas;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @mensaje = LEFT(ERROR_MESSAGE(), 500);
        EXEC dbo.sp_ETL_FinalizarControl @id, 'Fallido', 0, @mensaje;
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   Validación, coordinación y conciliación
   --------------------------------------------------------------------- */
-- Detecta registros del origen que no llegaron al DW e inconsistencias en los hechos.
CREATE OR ALTER PROCEDURE dbo.sp_ValidarCargaDW
    @problemas int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @r TABLE (verificacion varchar(100), cantidad int);

    INSERT INTO @r SELECT 'Lecturas sin hecho en FACT_CONSUMO', COUNT(*)
    FROM dbo.Lectura l WHERE NOT EXISTS (SELECT 1 FROM ASADA_DW.dbo.FACT_CONSUMO f WHERE f.id_lectura_origen = l.id_lectura);

    INSERT INTO @r SELECT 'Facturas sin hecho en FACT_FACTURACION', COUNT(*)
    FROM dbo.Factura x WHERE NOT EXISTS (SELECT 1 FROM ASADA_DW.dbo.FACT_FACTURACION f WHERE f.id_factura_origen = x.id_factura);

    INSERT INTO @r SELECT 'Pagos aplicados sin hecho en FACT_PAGO', COUNT(*)
    FROM dbo.Pago p WHERE p.estado = 'Aplicado'
      AND NOT EXISTS (SELECT 1 FROM ASADA_DW.dbo.FACT_PAGO f WHERE f.id_pago_origen = p.id_pago);

    INSERT INTO @r SELECT 'Pagos anulados que siguen en FACT_PAGO', COUNT(*)
    FROM ASADA_DW.dbo.FACT_PAGO f JOIN dbo.Pago p ON p.id_pago = f.id_pago_origen WHERE p.estado = 'Anulado';

    INSERT INTO @r SELECT 'Hechos de consumo con consumo incoherente', COUNT(*)
    FROM ASADA_DW.dbo.FACT_CONSUMO WHERE consumo_m3 <> lectura_actual - lectura_anterior OR consumo_m3 < 0;

    INSERT INTO @r SELECT 'Hechos de facturación con total incoherente', COUNT(*)
    FROM ASADA_DW.dbo.FACT_FACTURACION WHERE monto_total <> monto_consumo + monto_fijo;

    INSERT INTO @r SELECT 'Conexiones sin dimensión', COUNT(*)
    FROM dbo.Conexion c WHERE NOT EXISTS (SELECT 1 FROM ASADA_DW.dbo.DIM_CONEXION d WHERE d.id_conexion_origen = c.id_conexion);

    INSERT INTO @r SELECT 'Abonados sin dimensión', COUNT(*)
    FROM dbo.vw_Abonados a WHERE NOT EXISTS (SELECT 1 FROM ASADA_DW.dbo.DIM_ABONADO d
                                             WHERE d.tipo_abonado = a.tipo_abonado AND d.id_abonado_origen = a.id_abonado);

    SELECT @problemas = COUNT(*) FROM @r WHERE cantidad > 0;

    SELECT verificacion, cantidad, CASE WHEN cantidad = 0 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM @r;
END;
GO

-- Coordina toda la carga: dimensiones primero, luego cada hecho y al final la validación.
-- Si falla un hecho se continúa con los demás; al final el proceso termina con error
-- para que el job quede marcado como fallido.
CREATE OR ALTER PROCEDURE dbo.sp_EjecutarCargaDW
    @carga_completa bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @desde datetime = CASE WHEN @carga_completa = 1 THEN '19000101' END,
            @fallos int = 0, @problemas int, @desc varchar(max);

    EXEC dbo.sp_RegistrarEventoBitacora 'ETL', 'Control_ETL', 'Inicio de la carga del Data Warehouse.';

    BEGIN TRY
        EXEC dbo.sp_ETL_CargarDimensionesDW;
    END TRY
    BEGIN CATCH
        SET @desc = CONCAT('Carga del DW detenida: fallaron las dimensiones. ', ERROR_MESSAGE());
        EXEC dbo.sp_RegistrarEventoBitacora 'ETL', 'Control_ETL', @desc;
        THROW;
    END CATCH

    BEGIN TRY EXEC dbo.sp_ETL_CargaLecturasDW       @desde = @desde; END TRY BEGIN CATCH SET @fallos += 1; END CATCH
    BEGIN TRY EXEC dbo.sp_ETL_CargaFacturacionDW    @desde = @desde; END TRY BEGIN CATCH SET @fallos += 1; END CATCH
    BEGIN TRY EXEC dbo.sp_ETL_CargaMorosidadDW;                      END TRY BEGIN CATCH SET @fallos += 1; END CATCH
    BEGIN TRY EXEC dbo.sp_ETL_CargaMantenimientosDW @desde = @desde; END TRY BEGIN CATCH SET @fallos += 1; END CATCH

    EXEC dbo.sp_ValidarCargaDW @problemas = @problemas OUTPUT;

    SET @desc = CONCAT('Fin de la carga del DW. Procesos fallidos: ', @fallos, '. Validaciones con observaciones: ', @problemas, '.');
    EXEC dbo.sp_RegistrarEventoBitacora 'ETL', 'Control_ETL', @desc;

    SELECT * FROM dbo.vw_UltimaCargaPorTabla ORDER BY nombre_tabla_destino;

    IF @fallos > 0
        THROW 50901, 'Uno o más procesos ETL fallaron. Revise vw_CargasFallidas.', 1;
END;
GO

-- Compara cantidades e importes entre el origen y el DW para un periodo (AAAAMM).
CREATE OR ALTER PROCEDURE dbo.sp_ConciliarOrigenDW
    @periodo int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @desde date = DATEFROMPARTS(@periodo / 100, @periodo % 100, 1);
    DECLARE @hasta date = DATEADD(MONTH, 1, @desde);
    DECLARE @t_desde int = dbo.fn_IdTiempo(@desde), @t_hasta int = dbo.fn_IdTiempo(@hasta);

    SELECT CAST(N'Consumo (m³)' AS nvarchar(30)) AS medida,
           (SELECT COUNT(*)     FROM dbo.Lectura WHERE fecha_lectura_actual >= @desde AND fecha_lectura_actual < @hasta) AS cantidad_origen,
           (SELECT COUNT(*)     FROM ASADA_DW.dbo.FACT_CONSUMO WHERE id_tiempo >= @t_desde AND id_tiempo < @t_hasta)    AS cantidad_dw,
           (SELECT ISNULL(SUM(consumo), 0)    FROM dbo.Lectura WHERE fecha_lectura_actual >= @desde AND fecha_lectura_actual < @hasta) AS importe_origen,
           (SELECT ISNULL(SUM(consumo_m3), 0) FROM ASADA_DW.dbo.FACT_CONSUMO WHERE id_tiempo >= @t_desde AND id_tiempo < @t_hasta)    AS importe_dw
    INTO #c;

    INSERT INTO #c
    SELECT N'Facturación (₡)',
           (SELECT COUNT(*) FROM dbo.Factura WHERE fecha_emision >= @desde AND fecha_emision < @hasta),
           (SELECT COUNT(*) FROM ASADA_DW.dbo.FACT_FACTURACION WHERE id_tiempo >= @t_desde AND id_tiempo < @t_hasta),
           (SELECT ISNULL(SUM(monto_total), 0) FROM dbo.Factura WHERE fecha_emision >= @desde AND fecha_emision < @hasta),
           (SELECT ISNULL(SUM(monto_total), 0) FROM ASADA_DW.dbo.FACT_FACTURACION WHERE id_tiempo >= @t_desde AND id_tiempo < @t_hasta);

    INSERT INTO #c
    SELECT N'Pagos (₡)',
           (SELECT COUNT(*) FROM dbo.Pago WHERE estado = 'Aplicado' AND fecha_pago >= @desde AND fecha_pago < @hasta),
           (SELECT COUNT(*) FROM ASADA_DW.dbo.FACT_PAGO WHERE id_tiempo >= @t_desde AND id_tiempo < @t_hasta),
           (SELECT ISNULL(SUM(monto), 0) FROM dbo.Pago WHERE estado = 'Aplicado' AND fecha_pago >= @desde AND fecha_pago < @hasta),
           (SELECT ISNULL(SUM(monto_pagado), 0) FROM ASADA_DW.dbo.FACT_PAGO WHERE id_tiempo >= @t_desde AND id_tiempo < @t_hasta);

    SELECT medida, cantidad_origen, cantidad_dw, cantidad_origen - cantidad_dw AS diferencia_cantidad,
           importe_origen, importe_dw, importe_origen - importe_dw AS diferencia_importe,
           CASE WHEN cantidad_origen = cantidad_dw AND importe_origen = importe_dw THEN 'Conciliado' ELSE 'Diferencia' END AS resultado
    FROM #c;
END;
GO

/* ---------------------------------------------------------------------
   12.31 Control ETL
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarControlETL
    @nombre_tabla_destino varchar(50) = NULL,
    @estado               varchar(20) = NULL,
    @desde                datetime    = NULL,
    @hasta                datetime    = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT id_proceso_etl, nombre_tabla_destino, fecha_proceso, fecha_ultima_carga,
           filas_procesadas, estado, mensaje_error, reintentado
    FROM dbo.Control_ETL
    WHERE (@nombre_tabla_destino IS NULL OR nombre_tabla_destino = @nombre_tabla_destino)
      AND (@estado IS NULL OR estado = @estado)
      AND (@desde  IS NULL OR fecha_proceso >= @desde)
      AND (@hasta  IS NULL OR fecha_proceso <= @hasta)
    ORDER BY fecha_proceso DESC, id_proceso_etl DESC;
END;
GO

-- Vuelve a ejecutar el proceso de una carga fallida y la marca como reintentada.
CREATE OR ALTER PROCEDURE dbo.sp_ReintentarCargaETL
    @id_proceso_etl int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @tabla varchar(50);
    SELECT @tabla = nombre_tabla_destino FROM dbo.Control_ETL
    WHERE id_proceso_etl = @id_proceso_etl AND estado = 'Fallido' AND reintentado = 0;

    IF @tabla IS NULL
        THROW 50902, 'La carga no existe, no está fallida o ya fue reintentada.', 1;

    UPDATE dbo.Control_ETL SET reintentado = 1 WHERE id_proceso_etl = @id_proceso_etl;

    IF @tabla = 'DIMENSIONES'                       EXEC dbo.sp_ETL_CargarDimensionesDW;
    ELSE IF @tabla = 'FACT_CONSUMO'                 EXEC dbo.sp_ETL_CargaLecturasDW;
    ELSE IF @tabla IN ('FACT_FACTURACION', 'FACT_PAGO') EXEC dbo.sp_ETL_CargaFacturacionDW;
    ELSE IF @tabla = 'FACT_MOROSIDAD'               EXEC dbo.sp_ETL_CargaMorosidadDW;
    ELSE IF @tabla = 'FACT_MANTENIMIENTO'           EXEC dbo.sp_ETL_CargaMantenimientosDW;
    ELSE THROW 50903, 'No hay un proceso ETL asociado a esa tabla destino.', 1;
END;
GO
