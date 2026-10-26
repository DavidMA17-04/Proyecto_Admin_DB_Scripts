SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Script 03: Funciones
   --------------------------------------------------------------------- */
USE ASADA;
GO

   --Funciones de apoyo para la sesión de la aplicación
CREATE OR ALTER FUNCTION dbo.fn_UsuarioActual()
RETURNS int
AS
BEGIN
    RETURN CAST(SESSION_CONTEXT(N'id_usuario_sistema') AS int);
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_EmpleadoActual()
RETURNS int
AS
BEGIN
    RETURN CAST(SESSION_CONTEXT(N'id_empleado') AS int);
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_ValidarIdentificacion
(
    @tipo_identificacion varchar(20),
    @numero              varchar(50)
)
RETURNS bit
AS
BEGIN
    DECLARE @n varchar(50) = REPLACE(REPLACE(LTRIM(RTRIM(@numero)), '-', ''), ' ', '');

    IF @n IS NULL OR @n = '' RETURN 0;

    IF @tipo_identificacion = 'FISICA'
        RETURN CASE WHEN LEN(@n) = 9 AND @n NOT LIKE '%[^0-9]%' AND LEFT(@n, 1) <> '0' THEN 1 ELSE 0 END;

    IF @tipo_identificacion = 'JURIDICA'
        RETURN CASE WHEN LEN(@n) = 10 AND @n NOT LIKE '%[^0-9]%' AND LEFT(@n, 1) = '3' THEN 1 ELSE 0 END;

    IF @tipo_identificacion = 'DIMEX'
        RETURN CASE WHEN LEN(@n) IN (11, 12) AND @n NOT LIKE '%[^0-9]%' THEN 1 ELSE 0 END;

    IF @tipo_identificacion = 'NITE'
        RETURN CASE WHEN LEN(@n) = 10 AND @n NOT LIKE '%[^0-9]%' THEN 1 ELSE 0 END;

    IF @tipo_identificacion = 'PASAPORTE'
        RETURN CASE WHEN LEN(@n) BETWEEN 6 AND 20 AND @n NOT LIKE '%[^0-9A-Za-z]%' THEN 1 ELSE 0 END;

    RETURN 0;
END;
GO

-- Nombre completo del abonado físico o razón social del jurídico
CREATE OR ALTER FUNCTION dbo.fn_ObtenerNombreCompleto
(
    @id_abonado_fisico   int,
    @id_abonado_juridico int
)
RETURNS varchar(152)
AS
BEGIN
    DECLARE @nombre varchar(152);

    IF @id_abonado_fisico IS NOT NULL
        SELECT @nombre = CONCAT_WS(' ', nombre, apellido1, apellido2)
        FROM dbo.Abonado_Fisico
        WHERE id_abonado_fisico = @id_abonado_fisico;
    ELSE
        SELECT @nombre = razon_social
        FROM dbo.Abonado_Juridico
        WHERE id_abonado_juridico = @id_abonado_juridico;

    RETURN @nombre;
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_ObtenerTarifaVigente
(
    @id_conexion int,
    @fecha       datetime
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        t.id_tarifa,
        t.id_tipo_tarifa,
        COALESCE(h.monto_fijo_anterior,   t.monto_fijo)   AS monto_fijo,
        COALESCE(h.monto_por_m3_anterior, t.monto_por_m3) AS monto_por_m3
    FROM dbo.Conexion c
    JOIN dbo.Tarifa  t ON t.id_tarifa = c.id_tarifa
    OUTER APPLY (
        SELECT TOP (1) ht.monto_fijo_anterior, ht.monto_por_m3_anterior
        FROM dbo.Historial_Tarifa ht
        WHERE ht.id_tarifa = t.id_tarifa
          AND ht.fecha_cambio > @fecha
        ORDER BY ht.fecha_cambio ASC
    ) h
    WHERE c.id_conexion = @id_conexion
);
GO

-- Usada por CK_Tarifa_TipoValido: el tipo de tarifa debe existir y estar activo
CREATE OR ALTER FUNCTION dbo.fn_TipoTarifaActivo (@id_tipo_tarifa int)
RETURNS bit
AS
BEGIN
    RETURN CASE WHEN EXISTS (SELECT 1 FROM dbo.Tipo_Tarifa
                             WHERE id_tipo_tarifa = @id_tipo_tarifa AND activo = 1)
                THEN 1 ELSE 0 END;
END;
GO

ALTER TABLE dbo.Tarifa WITH CHECK
    ADD CONSTRAINT CK_Tarifa_TipoValido CHECK (dbo.fn_TipoTarifaActivo(id_tipo_tarifa) = 1);
GO

-- Última lectura registrada del medidor
CREATE OR ALTER FUNCTION dbo.fn_ObtenerUltimaLectura (@id_medidor int)
RETURNS decimal(10,2)
AS
BEGIN
    DECLARE @ultima decimal(10,2);

    SELECT @ultima = ultima_lectura
    FROM dbo.Medidor
    WHERE id_medidor = @id_medidor;

    -- Si el campo desnormalizado está vacío, se consulta la tabla de lecturas
    IF @ultima IS NULL
        SELECT TOP (1) @ultima = lectura_actual
        FROM dbo.Lectura
        WHERE id_medidor = @id_medidor
        ORDER BY fecha_lectura_actual DESC, id_lectura DESC;

    RETURN ISNULL(@ultima, 0);
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_CalcularConsumo
(
    @lectura_anterior decimal(10,2),
    @lectura_actual   decimal(10,2)
)
RETURNS decimal(10,2)
AS
BEGIN
    IF @lectura_actual < @lectura_anterior RETURN NULL;
    RETURN @lectura_actual - @lectura_anterior;
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_CalcularPromedioConsumo
(
    @id_medidor int,
    @meses      int,
    @antes_de   datetime
)
RETURNS decimal(10,2)
AS
BEGIN
    DECLARE @promedio decimal(10,2);

    SELECT @promedio = AVG(consumo)
    FROM (
        SELECT TOP (@meses) consumo
        FROM dbo.Lectura
        WHERE id_medidor = @id_medidor
          AND fecha_lectura_actual < @antes_de
        ORDER BY fecha_lectura_actual DESC
    ) ultimas;

    RETURN @promedio;
END;
GO

-- Variación porcentual respecto al promedio. NULL cuando el promedio es 0,
-- para que el procedimiento decida cómo aplicar la regla.
CREATE OR ALTER FUNCTION dbo.fn_CalcularPorcentajeVariacion
(
    @consumo_promedio decimal(10,2),
    @consumo_actual   decimal(10,2)
)
RETURNS decimal(7,2)
AS
BEGIN
    IF @consumo_promedio IS NULL OR @consumo_promedio = 0 RETURN NULL;

    DECLARE @variacion decimal(18,2) = (@consumo_actual - @consumo_promedio) * 100.0 / @consumo_promedio;

    -- Tope para no desbordar decimal(7,2)
    RETURN CASE WHEN @variacion > 99999.99 THEN 99999.99 ELSE @variacion END;
END;
GO

-- 1 si el consumo actual supera el umbral de la regla
-- Sin historial (promedio NULL) no se puede comparar y no se alerta
-- Con promedio 0 (p. ej. casa deshabitada) es anómalo si supera el consumo mínimo de la regla
CREATE OR ALTER FUNCTION dbo.fn_EsConsumoAnomalo
(
    @consumo_promedio     decimal(10,2),
    @consumo_actual       decimal(10,2),
    @porcentaje_variacion decimal(5,2),
    @consumo_minimo       decimal(10,2)
)
RETURNS bit
AS
BEGIN
    IF @consumo_promedio IS NULL RETURN 0;
    IF @consumo_actual < @consumo_minimo RETURN 0;

    IF @consumo_promedio = 0
        RETURN CASE WHEN @consumo_minimo > 0 THEN 1 ELSE 0 END;

    RETURN CASE WHEN dbo.fn_CalcularPorcentajeVariacion(@consumo_promedio, @consumo_actual) >= @porcentaje_variacion
                THEN 1 ELSE 0 END;
END;
GO

-- Monto total a facturar: monto fijo + consumo × monto por m³
CREATE OR ALTER FUNCTION dbo.fn_CalcularMontoFactura
(
    @consumo_m3   decimal(10,2),
    @monto_fijo   decimal(10,2),
    @monto_por_m3 decimal(10,2)
)
RETURNS decimal(10,2)
AS
BEGIN
    RETURN ROUND(@monto_fijo + (@consumo_m3 * @monto_por_m3), 2);
END;
GO

-- Saldo = total de la factura + recargos aplicados - pagos aplicados
CREATE OR ALTER FUNCTION dbo.fn_CalcularSaldoPendiente (@id_factura int)
RETURNS decimal(10,2)
AS
BEGIN
    DECLARE @total decimal(10,2), @recargos decimal(10,2), @pagos decimal(10,2);

    SELECT @total = monto_total FROM dbo.Factura WHERE id_factura = @id_factura;

    SELECT @recargos = ISNULL(SUM(monto_recargo), 0)
    FROM dbo.Recargo_mora
    WHERE id_factura = @id_factura AND estado = 'Aplicado';

    SELECT @pagos = ISNULL(SUM(monto), 0)
    FROM dbo.Pago
    WHERE id_factura = @id_factura AND estado = 'Aplicado';

    RETURN @total + @recargos - @pagos;
END;
GO

-- Porcentaje de recargo según días de atraso. Los tramos se configuran en la
-- tabla Tramo_Mora (por defecto: 1-30 días 2 %, 31-60 días 4 %, más de 60 días 6 %).
CREATE OR ALTER FUNCTION dbo.fn_CalcularPorcentajeMora (@dias_atraso int)
RETURNS decimal(5,2)
AS
BEGIN
    DECLARE @porcentaje decimal(5,2);

    IF @dias_atraso <= 0 RETURN 0;

    SELECT TOP (1) @porcentaje = t.porcentaje
    FROM dbo.Tramo_Mora t
    WHERE t.activo = 1
      AND t.dias_desde <= @dias_atraso
      AND (t.dias_hasta IS NULL OR t.dias_hasta >= @dias_atraso)
    ORDER BY t.dias_desde DESC;

    RETURN ISNULL(@porcentaje, 0);
END;
GO

-- Horas entre el reporte y la resolución. NULL si la incidencia sigue abierta
CREATE OR ALTER FUNCTION dbo.fn_CalcularTiempoResolucion (@id_incidencia int)
RETURNS int
AS
BEGIN
    DECLARE @apertura datetime, @cierre datetime;

    SELECT @apertura = fecha_incidente FROM dbo.Incidencia WHERE id_incidencia = @id_incidencia;

    SELECT @cierre = MAX(fecha_evento)
    FROM dbo.Historial_Incidencia
    WHERE id_incidencia = @id_incidencia AND estado_actual = 'Resuelta';

    IF @cierre IS NULL RETURN NULL;
    RETURN DATEDIFF(HOUR, @apertura, @cierre);
END;
GO

-- Prioridad de la incidencia según palabras clave de la descripción y el tipo
CREATE OR ALTER FUNCTION dbo.fn_ClasificarIncidencia
(
    @descripcion        varchar(100),
    @id_tipo_incidencia int
)
RETURNS varchar(10)
AS
BEGIN
    DECLARE @texto varchar(150) = LOWER(CONCAT(@descripcion, ' ',
        (SELECT nombre_incidencia FROM dbo.Tipo_Incidencia WHERE id_tipo_incidencia = @id_tipo_incidencia)));

    IF @texto LIKE '%fuga%' OR @texto LIKE '%sin agua%' OR @texto LIKE '%rotura%'
       OR @texto LIKE '%tuber%' OR @texto LIKE '%contamina%'
        RETURN 'Alta';

    IF @texto LIKE '%medidor%' OR @texto LIKE '%daño%' OR @texto LIKE '%presi%'
        RETURN 'Media';

    RETURN 'Baja';
END;
GO

--Horas entre el inicio y el cierre del mantenimiento. NULL si no ha finalizado
CREATE OR ALTER FUNCTION dbo.fn_CalcularDuracionMantenimiento (@id_mantenimiento int)
RETURNS int
AS
BEGIN
    DECLARE @horas int;

    SELECT @horas = DATEDIFF(HOUR, fecha_inicio, fecha_fin)
    FROM dbo.Mantenimiento
    WHERE id_mantenimiento = @id_mantenimiento AND fecha_fin IS NOT NULL;

    RETURN @horas;
END;
GO

-- Periodo (AAAAMM) al que corresponde una fecha
CREATE OR ALTER FUNCTION dbo.fn_ObtenerPeriodoFiscal (@fecha datetime)
RETURNS int
AS
BEGIN
    RETURN YEAR(@fecha) * 100 + MONTH(@fecha);
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_CalcularDuracionRespaldo (@id_respaldo int)
RETURNS int
AS
BEGIN
    DECLARE @segundos int;

    SELECT @segundos = DATEDIFF(SECOND, fecha_inicio, fecha_fin)
    FROM dbo.Historial_Respaldo
    WHERE id_respaldo = @id_respaldo;

    RETURN @segundos;
END;
GO

-- Fecha hasta la cual debe conservarse el respaldo. No elimina archivos
CREATE OR ALTER FUNCTION dbo.fn_CalcularFechaRetencionRespaldo (@id_respaldo int)
RETURNS datetime
AS
BEGIN
    DECLARE @fecha datetime;

    SELECT @fecha = DATEADD(DAY, p.retencion_dias, h.fecha_inicio)
    FROM dbo.Historial_Respaldo h
    JOIN dbo.Politica_Respaldo  p ON p.id_politica = h.id_politica
    WHERE h.id_respaldo = @id_respaldo;

    RETURN @fecha;
END;
GO

-- Mínimo 8 caracteres, con mayúscula, minúscula, número y símbolo
CREATE OR ALTER FUNCTION dbo.fn_ValidarComplejidadContrasena (@contrasena nvarchar(128))
RETURNS bit
AS
BEGIN
    IF @contrasena IS NULL OR LEN(@contrasena) < 8 RETURN 0;

    -- Collation binaria para distinguir mayúsculas de minúsculas
    IF PATINDEX(N'%[A-Z]%',        @contrasena COLLATE Latin1_General_BIN) = 0 RETURN 0;
    IF PATINDEX(N'%[a-z]%',        @contrasena COLLATE Latin1_General_BIN) = 0 RETURN 0;
    IF PATINDEX(N'%[0-9]%',        @contrasena) = 0 RETURN 0;
    IF PATINDEX(N'%[^A-Za-z0-9]%', @contrasena COLLATE Latin1_General_BIN) = 0 RETURN 0;

    RETURN 1;
END;
GO

-- Hash SHA2-256 de la contraseña. Se usa el nombre de usuario como "sal"
-- para que dos usuarios con la misma contraseña no tengan el mismo hash
CREATE OR ALTER FUNCTION dbo.fn_HashContrasena
(
    @nombre_usuario varchar(50),
    @contrasena     nvarchar(128)
)
RETURNS varchar(64)
AS
BEGIN
    RETURN CONVERT(varchar(64),
                   HASHBYTES('SHA2_256', CONCAT(LOWER(@nombre_usuario), N'|', @contrasena)),
                   2);
END;
GO

-- RA1: verifica si un usuario activo tiene un permiso por medio de su rol.
CREATE OR ALTER FUNCTION dbo.fn_TienePermiso
(
    @id_usuario_sistema int,
    @nombre_permiso     varchar(50)
)
RETURNS bit
AS
BEGIN
    RETURN CASE WHEN EXISTS (
        SELECT 1
        FROM dbo.Usuario_Sistema u
        JOIN dbo.Rol_permiso     rp ON rp.id_rol = u.id_rol
        JOIN dbo.Permiso         p  ON p.id_permiso = rp.id_permiso
        WHERE u.id_usuario_sistema = @id_usuario_sistema
          AND u.activo = 1
          AND p.nombre_permiso = @nombre_permiso
    ) THEN 1 ELSE 0 END;
END;
GO
